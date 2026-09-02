# Depois da rodada — o que rodar, e como entregar

Este arquivo existe por uma limitação que não vai mudar: **a sessão de agente não alcança o n8n
nem o Supabase de produção.** A rodada acontece onde eu não vejo. O que decide se o problema é
resolvido na primeira resposta ou na quarta é **a evidência que chega junto com o pedido**.

"Deu erro no documento 17" custa três rodadas de perguntas. A saída das quatro consultas abaixo
custa zero.

> **Todas as consultas são somente leitura** e se acham sozinhas o mandato mais recente — não há
> nada para editar, é copiar e colar no **SQL Editor do Supabase**. Se quiser mirar outro mandato,
> troque a linha `with alvo as (...)` por `with alvo as (select id from caso where nome = 'NOME')`.
>
> **As quatro foram executadas contra um Postgres 16 com as 101 migrations antes de entrarem aqui**
> — exatamente como estão escritas, copiadas deste arquivo. Duas delas eu tinha escrito à mão e
> reprovaram (`ce.escala` e `p.decisao` não existem: são `ce.unidade` e `p.estado`); as versões
> abaixo vêm **verbatim** de `Supabase/diagnostico_rodada.sql` e `Supabase/pendencias_do_mandato.sql`,
> com só a linha do `alvo` trocada. Consulta que não roda no editor custa a sua rodada, não a minha.

---

## ANTES de subir documento (30 segundos, e evita a rodada morta)

**A.** No terminal, com a URL de produção:

```bash
CONFERIR_PSQL="psql 'postgresql://…@…supabase.co:5432/postgres'" \
  node Supabase/test/conferir-chamadas.mjs
```

`0` = tudo o que o n8n e o portal chamam existe · `1` = achei chamada quebrada (ele nomeia o nó) ·
`2` = não consegui perguntar, **que não é "passou"**.

**B.** No SQL Editor:

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

Zero linha = instalação completa. As duas juntas cobrem os dois lados: a **A** pergunta "o que o
código chama existe aqui?", a **B** pergunta "o que este banco sabe que deveria ter está aqui?".
Nenhuma das duas sozinha basta — foi o que a sessão 78 mediu.

---

## DEPOIS da rodada — as quatro, nesta ordem

### 1. O lote: começou? terminou? quanto custou?

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

**É a consulta mais importante das quatro, e o primeiro campo a olhar é `estado`.**
`*** COMECOU E NAO TERMINOU ***` significa `fechado_em` nulo — a rodada morreu no meio. Foi para
distinguir isso de "nunca rodou" que a `0156` existe: a rodada de 190 de 27/08 foi cancelada e não
deixou rastro nenhum.

**`sem_medicao` é o alerta mais sério e o menos óbvio:** não é cobertura *baixa*, é a guarda **não
ter opinado** sobre o documento. Silêncio não é aprovação.

Se a consulta devolver **zero linhas** depois de uma rodada, o `workflow.e1-ingestao.json` não foi
reimportado no n8n — o nó `Abrir Lote` não está no canvas em execução.

### 2. Documento a documento: o que saiu de cada um

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

É a versão auto-alvo de `Supabase/diagnostico_rodada.sql`. Um documento com
`pares_conta_coluna = 0` não entregou linha nenhuma; `linhas_sem_secao` alto é extração sem forma;
`escala` ou `moeda` nulos são a origem do erro de ~496× que o `HANDOFF` registra.

### 3. O que o sistema declarou que precisa de humano

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

Versão auto-alvo de `Supabase/pendencias_do_mandato.sql`. `bloqueante` impede o aceite do mandato;
`sobrepujavel` é a diferença entre "alguém decide e segue" e "não tem como seguir".

### 4. O arquivo entregue

Exporte o completo pelo portal e rode no terminal:

```bash
./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <caminho/do/arquivo.xlsx>
```

Sai com código 1 se qualquer item obrigatório reprovar. **É sobre o arquivo da rodada REAL que ele
vale** — sobre fixture ele já roda no CI todo dia.

---

## Como me entregar — o formato que dispensa pergunta

Cole numa mensagem só, nesta ordem, cada bloco com o título:

```
## 1. LOTE
<cole a tabela inteira da consulta 1>

## 2. DOCUMENTOS
<cole a tabela inteira da consulta 2>

## 3. PENDÊNCIAS
<cole a tabela inteira da consulta 3>

## 4. AUDITAR-XLSX
<cole a saída inteira, inclusive o código de saída>

## 5. O QUE EU VI
<uma linha por coisa que te pareceu errada, dizendo o ARQUIVO e o que o documento
 REALMENTE diz — o número certo, não só "está errado">
```

**As três coisas que mais economizam ida e volta:**

1. **A tabela inteira, não um resumo.** "Cobertura baixa" me faz perguntar quanto, em qual
   documento, contra qual denominador. A tabela responde as três de uma vez. No SQL Editor do
   Supabase há um botão de copiar o resultado — use ele, não digite.
2. **O `execucao_ref`** (vem na consulta 1). É o que liga o que está no banco à execução no n8n, e
   sem ele eu não sei de qual rodada estamos falando quando houver mais de uma.
3. **Quando um número saiu errado, o número CERTO.** "O ativo circulante do doc 09 saiu 7.254 e o
   documento diz 3.961" me dá a causa em minutos. "O balanço está errado" não.

**Se um nó do n8n morreu:** cole também a mensagem de erro do nó (n8n → Executions → a execução →
clique no nó vermelho). Antes disso, rode a conferência **A** lá de cima: se for objeto ausente no
banco, a resposta sai em dois segundos e não precisa de mais nada.

**Se um documento extraiu errado e não dá para saber por quê:** o texto que o nó `Extrair Texto`
produziu para aquele documento vale mais que qualquer descrição. É o campo `text` do item no
Output daquele nó.

---

## O que eu vou fazer com isso, e o que você deve cobrar de mim

A parte que impede o problema de **voltar** não é comando nenhum — é a doutrina do `CLAUDE.md`. Se
eu pular algum destes, me pare:

1. **Causa raiz antes de correção.** Três correções falhas seguidas param a linha e questionam a
   arquitetura; não existe quarta tentativa.
2. **Invariante MEDIDO não-vazio.** Toda correção fecha com um assert que **reprova com o bug
   ligado**. Se eu disser "acrescentei teste" sem dizer **quantos asserts reprovaram**, o teste
   pode ter nascido vazio — cobre o número.
3. **Portão, não só conserto.** Se o defeito só apareceu porque nada acusava, o entregável é o que
   passa a acusar. O caso de 02/09 é o exemplo: o problema não era a migration faltando, era
   **nada dizer que faltava**.
4. **Memória**, quando uma sessão futura ficaria surpresa e grata de saber antes de começar.

E uma advertência sobre os comandos importados (`.claude/commands/`): **não comece por
`/smart-fix` nem `/full-review`.** Eles pulam para a correção e não conhecem a lente central deste
projeto — o defeito que não produz erro. Servem como segunda opinião depois que a causa está
estabelecida, nunca como primeira parada.

---

## Antes de fechar o mandato

O critério de pronto do B1 (`MAPA_DE_EXECUCAO.md`) é o `ACEITE.md` preenchido, com os itens do
`auditar-xlsx.mts` verdes **sobre o arquivo exportado da rodada real** — não sobre fixture. As
onze coisas que só a rodada prova estão listadas lá.
