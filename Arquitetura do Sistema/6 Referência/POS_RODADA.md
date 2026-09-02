# Depois da rodada — passo a passo, sem terminal

Este arquivo existe por uma limitação que não vai mudar: **a sessão de agente não alcança o n8n
nem o Supabase de produção.** A rodada acontece onde o Claude não vê. O que decide se o problema é
resolvido na primeira resposta ou na quarta é **a evidência que chega junto com o pedido**.

"Deu erro no documento 17" custa três rodadas de perguntas. A saída das consultas abaixo custa zero.

> **Você não precisa de terminal.** Tudo aqui é: abrir uma aba, colar um bloco, copiar o resultado.
> A primeira versão deste arquivo mandava rodar comandos numa linha de comando — que pressupõe o
> repositório clonado, Node instalado e dependências baixadas. **Isso foi substituído por SQL** que
> roda no painel do Supabase. O que sobrou de terminal virou "anexe o arquivo na conversa".

---

## Os três lugares, e só três

| # | Lugar | Como chegar |
|---|---|---|
| **A** | **SQL Editor do Supabase** | [supabase.com/dashboard](https://supabase.com/dashboard) → seu projeto → menu da esquerda, **SQL Editor** → **New query** |
| **B** | **n8n** | sua instância → **Executions** (só quando um nó morrer) |
| **C** | **A conversa com o Claude** | onde você cola os resultados e anexa o `.xlsx` |

Em **A**, o ciclo é sempre o mesmo: cole o bloco na caixa de texto → botão **Run** (ou `Ctrl+Enter`)
→ o resultado aparece embaixo → passe o mouse sobre a tabela e use **Copy** (ou selecione tudo e
`Ctrl+C`) → cole em **C**.

---

## PASSO 1 — Antes de subir documento (1 minuto, e evita a rodada morta)

### 1.1 — O que o n8n chama existe no banco?

**Onde:** SQL Editor (lugar **A**). **O que colar:** o conteúdo do arquivo
[`Supabase/conferir/conferir_chamadas.sql`](../../Supabase/conferir/conferir_chamadas.sql) — abra
no GitHub, clique em **Raw**, copie tudo, cole e rode.

O resultado é uma linha só:

- `PODE RODAR — as 15 chamadas do n8n resolvem neste banco` → **siga**.
- `*** NAO RODE ***` → **pare.** A segunda tabela diz qual nó e qual função. Cole as duas tabelas
  na conversa: quase sempre é migration que falta aplicar, e o Claude responde em segundos.

### 1.2 — A sonda de instalação

**Onde:** SQL Editor.

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

**Zero linhas = instalação completa.** Se vier alguma, cole na conversa.

> **As duas juntas cobrem lados diferentes, e nenhuma basta sozinha.** A 1.1 pergunta *"o que o
> código chama existe aqui?"*; a 1.2 pergunta *"o que este banco sabe que deveria ter está aqui?"*.
> Em 02/09 foi medido um banco em que a **1.2 não acusava nada** e **três chamadas do workflow não
> resolviam** — a rodada morreria no primeiro nó.

---

## PASSO 2 — Rode o book no portal

Mandato **novo** (não reaproveite: documento repetido não chama a IA de novo, e a rodada não prova
nada). Suba os documentos e espere terminar.

---

## PASSO 3 — As consultas, nesta ordem

Todas são **só leitura** e acham sozinhas o mandato mais recente. Nada para editar.

### 3.1 — O lote: começou? terminou? quanto custou?

```sql
select
  c.nome                                        as mandato,
  l.execucao_ref,
  l.criado_em                                   as comecou,
  l.fechado_em,
  case when l.fechado_em is null
       then '*** COMECOU E NAO TERMINOU ***'
       else 'fechou' end                        as estado,
  l.documentos_planejados, l.documentos,
  l.documentos_fatiados                         as fatiados,
  l.documentos_com_falha                        as com_falha,
  l.documentos_sem_medicao                      as sem_medicao,
  l.linhas_extraidas,
  round(l.cobertura, 3)                         as cobertura,
  round(l.custo_total_usd, 4)                   as custo_usd,
  round(l.custo_estimado_usd, 4)                as custo_previsto,
  o.alertas
from lote_execucao l
join caso c on c.id = l.caso_id
left join fn_operacao_lotes() o on o.lote_id = l.id
order by l.criado_em desc
limit 5;
```

**É a mais importante, e o primeiro campo a olhar é `estado`:**

| O que aparece | O que significa |
|---|---|
| `fechou` | a rodada foi até o fim |
| `*** COMECOU E NAO TERMINOU ***` | morreu no meio — vá ao **PASSO 5** |
| **nenhuma linha** | o workflow do n8n **não foi reimportado** — o nó `Abrir Lote` não está no canvas |

**`sem_medicao` é o alerta mais sério e o menos óbvio:** não é cobertura *baixa*, é a guarda **não
ter opinado** sobre o documento. Silêncio não é aprovação.

### 3.2 — Documento a documento

```sql
with alvo as (select id from caso order by criado_em desc limit 1)
select
  dv.nome_original                                             as arquivo,
  d.tipo_taxonomia                                             as tipo,
  round(d.confianca, 2)                                        as confianca,
  d.fonte                                                      as classificado_por,
  dv.legibilidade,
  dv.assinado,
  count(distinct ce.id)                                        as pares_conta_coluna,
  count(distinct ce.chave)                                     as contas_distintas,
  count(distinct ce.periodo_coluna)                            as colunas,
  count(distinct ce.entidade_coluna)                           as entidades_na_planilha,
  max(ce.unidade)                                              as escala,
  max(ce.moeda)                                                as moeda,
  round(avg(ce.confianca), 2)                                  as confianca_media_das_linhas,
  count(distinct ce.secao_canonica)                            as secoes_canonicas,
  count(*) filter (where ce.secao_canonica is null)            as linhas_sem_secao,
  (select count(*) from pendencia p
     where p.documento_id = d.id and p.estado = 'aberta')      as pendencias_abertas,
  (select string_agg(distinct p.tipo::text, ', ') from pendencia p
     where p.documento_id = d.id and p.estado = 'aberta')      as tipos_de_pendencia,
  left(coalesce(d.justificativa, ''), 180)                     as porque_classificou_assim,
  left(coalesce(dv.nota_legibilidade, ''), 180)                as nota_de_legibilidade
from documento d
join alvo on alvo.id = d.caso_id
left join documento_versao dv on dv.documento_id = d.id
left join campo_extraido ce on ce.documento_versao_id = dv.id
group by d.id, dv.id, dv.nome_original, d.tipo_taxonomia, d.confianca, d.fonte,
         dv.legibilidade, dv.assinado, d.justificativa, dv.nota_legibilidade
order by dv.nome_original;
```

`pares_conta_coluna = 0` → o documento não entregou linha nenhuma. `linhas_sem_secao` alto →
extração sem forma. `escala` ou `moeda` vazios → é a origem do erro de ~496× que o `HANDOFF`
registra.

### 3.3 — O que precisa de humano

```sql
with alvo as (select id from caso order by criado_em desc limit 1)
select
  p.severidade, p.tipo, p.origem_estagio,
  dv.nome_original as arquivo,
  left(coalesce(p.descricao, ''), 400) as descricao,
  left(coalesce(p.motivo, ''), 400)    as motivo,
  p.sobrepujavel, p.criada_em
from pendencia p
join alvo on alvo.id = p.caso_id
left join documento d on d.id = p.documento_id
left join documento_versao dv on dv.documento_id = d.id
where p.estado = 'aberta'
order by
  case p.severidade::text when 'bloqueante' then 1 when 'alta' then 2 when 'media' then 3 else 4 end,
  p.tipo, dv.nome_original;
```

`bloqueante` impede o aceite do mandato. `sobrepujavel` é a diferença entre "alguém decide e segue"
e "não tem como seguir".

### 3.4 — POR QUE falhou: são DUAS perguntas diferentes, não uma

**Não confunda as duas, e o `documentos_com_falha` da 3.1 responde só à segunda.** Medido em
02/09, na primeira rodada real: `com_falha = 1` e a tabela de execução **vazia** — as duas coisas
certas ao mesmo tempo.

| Pergunta | Onde está | O que significa vir vazio |
|---|---|---|
| **(a)** Um nó do n8n morreu? | `execucao_falha` (3.4a) | **nenhum nó morreu** — é resposta, não ausência de dado |
| **(b)** Um documento falhou na extração? | pendência `extracao_falhou` (3.4b) | nenhum documento falhou |

`documentos_com_falha` é contado **pelo próprio n8n** (`if (e.falha_motivo) comFalha += 1`), a
partir da extração de cada documento. Ele não olha `execucao_falha`, e a tabela pode estar vazia
com `com_falha` alto: foi exatamente o que aconteceu.

#### 3.4a — algum nó morreu?

```sql
select
  f.caso_nome                              as mandato,
  f.criado_em,
  f.etapa,
  left(f.mensagem, 300)                    as mensagem,
  jsonb_pretty(f.detalhe)                  as detalhe,
  case when f.visto_em is null then 'NAO VISTA' else 'vista' end as estado
from execucao_falha f
order by f.criado_em desc
limit 50;
```

Vazio aqui é **boa notícia e resposta completa**: nenhum nó do n8n quebrou. Não filtra por
mandato de propósito — falha de rodada anterior é contexto.

#### 3.4b — qual documento falhou na extração, e por quê

```sql
select
  c.nome                                as mandato,
  dv.nome_original                      as arquivo,
  p.criada_em,
  p.descricao,
  left(coalesce(p.motivo, ''), 200)     as motivo
from pendencia p
join caso c on c.id = p.caso_id
left join documento d on d.id = p.documento_id
left join documento_versao dv on dv.documento_id = d.id
where p.tipo = 'extracao_falhou'
order by p.criada_em desc
limit 60;
```

**É esta que responde ao `documentos_com_falha`.** A `descricao` traz o motivo por extenso, que o
extrator escreveu: "não trouxe NENHUMA linha", "truncada por limite de tokens de saída
(`finish_reason=length`)", "3 linhas repetidas na emenda entre blocos foram descartadas".

Ela também não filtra por mandato, e é aqui — não na 3.4a — que se procura o motivo de uma rodada
antiga que falhou em massa.

---

## PASSO 4 — Exporte e ANEXE (aqui morava o terminal)

Exporte o completo pelo portal. **Anexe o `.xlsx` na conversa** — o Claude roda o auditor
(`portal/scripts/auditar-xlsx.mts`, 10 itens obrigatórios) e devolve o resultado. Você não roda nada.

---

## PASSO 5 — Se um nó do n8n morreu

**Onde:** n8n → **Executions** → a execução da rodada → clique no **nó vermelho** → aba **Output**
(ou o balão de erro). Copie a mensagem inteira e cole na conversa.

Se um documento extraiu errado e não dá para saber por quê, o mesmo caminho serve para o texto:
nó **`Extrair Texto`** → **Output** → o item daquele documento → copie o campo **`text`**. Esse
texto vale mais que qualquer descrição — foi com ele que a régua de cobertura foi corrigida.

---

## PASSO 6 — Como mandar, para não haver pergunta de volta

Numa mensagem só, com os títulos:

```
## 1. LOTE
<cole a tabela da 3.1>

## 2. DOCUMENTOS
<cole a tabela da 3.2>

## 3. PENDÊNCIAS
<cole a tabela da 3.3>

## 3b. FALHAS   (só se com_falha > 0)
<cole a 3.4a e a 3.4b — as duas, mesmo que uma venha vazia:
 vazio na 3.4a significa "nenhum nó morreu", e isso é informação>

## 4. O QUE EU VI
<uma linha por coisa errada, com o ARQUIVO e o número CERTO>
```

E anexe o `.xlsx`.

**As três coisas que mais economizam ida e volta:**

1. **A tabela inteira, não um resumo.** "Cobertura baixa" faz o Claude perguntar quanto, em qual
   documento, contra qual denominador. A tabela responde as três de uma vez.
2. **O `execucao_ref`** (vem na 3.1). É o que liga o que está no banco à execução no n8n.
3. **O número CERTO quando um número sai errado.** "O ativo circulante do doc 09 saiu 7.254 e o
   documento diz 3.961" dá a causa em minutos. "O balanço está errado" não dá.

---

## O que cobrar do Claude, para o defeito não voltar

Esta é a parte que impede o problema de **reaparecer**, e não é comando nenhum:

1. **Causa raiz antes de correção.** Três correções falhas seguidas param a linha e questionam a
   arquitetura; não existe quarta tentativa.
2. **Invariante MEDIDO não-vazio.** Toda correção fecha com um teste que **reprova com o bug
   ligado**. Se ele disser "acrescentei teste" sem dizer **quantos asserts reprovaram**, o teste
   pode ter nascido vazio — cobre o número.
3. **Portão, não só conserto.** Se o defeito só apareceu porque nada acusava, o entregável é o que
   passa a acusar.
4. **Memória**, quando uma sessão futura ficaria surpresa e grata de saber antes de começar.

E sobre os comandos importados em `.claude/commands/`: **não comece por `/smart-fix` nem
`/full-review`.** Eles pulam para a correção e não conhecem a lente central deste projeto — o
defeito que não produz erro. Servem como segunda opinião depois que a causa está estabelecida.

---

## Antes de fechar o mandato

O critério de pronto do B1 (`MAPA_DE_EXECUCAO.md`) é o `ACEITE.md` preenchido, com os 10 itens do
auditor verdes **sobre o arquivo exportado da rodada real** — não sobre fixture. As onze coisas que
só a rodada prova estão listadas lá.
