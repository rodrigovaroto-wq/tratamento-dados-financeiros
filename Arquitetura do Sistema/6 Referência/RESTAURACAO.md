# Teste de restauração — o que transforma "temos backup" em controle

> **Por que existe.** `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md` §3 diz:
> *"um procedimento de restauração que nunca foi executado não é um procedimento"*. Este arquivo é o
> procedimento, no nível de detalhe que permite executá-lo em uma sentada — e o lugar onde o
> resultado fica anotado, porque **"temos backup" e "voltamos em 40 minutos" são respostas
> diferentes, e só a segunda serve para dizer a um cliente.**

**Faça uma vez.** Repita quando trocar de plano, de região, ou depois de qualquer mudança grande de
schema.

> **Sobre os nomes de menu.** O console do Supabase muda de rótulo com alguma frequência. Abaixo
> está **o que procurar**, não um caminho de cliques garantido. As **consultas SQL são exatas** e
> não mudam.

---

## Parte 1 — as três respostas que o console já tem (3 minutos)

Estas fecham três dos `[A CONFIRMAR]` da especificação §3, e você as lê sem restaurar nada.

| Onde olhar | O que anotar | Fecha |
|---|---|---|
| **Settings → General** (ou a página inicial do projeto) | A **região** do projeto | §1, linha do Supabase/Postgres |
| **Settings → Billing / Subscription** | O **plano**, e a **retenção de backup** que ele dá (o Free não tem backup gerenciado — se for esse o caso, **pare aqui e me diga**: a conclusão do teste muda completamente) | §3 |
| **Database → Backups** | Se o **PITR** está ligado, e desde quando | §3 |

Anote as três na Parte 4 antes de continuar.

---

## Parte 2 — restaurar num projeto DESCARTÁVEL (o teste em si)

**Nunca restaure sobre o projeto de produção para testar.** O objetivo é provar que o dado volta,
não arriscar o que está de pé.

Em **Database → Backups**, você vai ter um destes dois caminhos, dependendo do plano:

- **Download do backup** (um dump `.sql`/`.tar`) → crie um projeto novo, descartável, e carregue o
  dump nele. É o caminho mais provável e o mais fácil de conferir.
- **PITR / restore gerenciado** → siga o fluxo do console, apontando para o projeto descartável.

**Comece a contar o tempo aqui.** O número que interessa é do início da restauração até a Parte 3
responder verde.

---

## Parte 3 — provar que o banco restaurado é o banco esperado

Conectado ao **projeto restaurado** (não à produção), no SQL Editor.

### 3.1 — A sonda: o banco tem tudo que deveria ter?

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

**Zero linhas** é o esperado. Se vier alguma, o backup restaurou um banco anterior àquela migration
— anote quais e me mande.

### 3.2 — O dado do cliente veio junto, não só o schema?

Esta é a pergunta que a sonda **não** responde: ela conhece objetos, não linhas.

```sql
select
  (select count(*) from caso)              as casos,
  (select count(*) from documento)         as documentos,
  (select count(*) from documento_versao)  as versoes,
  (select count(*) from campo_extraido)    as campos_extraidos,
  (select count(*) from pendencia)         as pendencias,
  (select count(*) from evento_auditoria)  as trilha,
  (select count(*) from lote_execucao)     as lotes;
```

Compare com a produção. **Não precisam bater exatamente** — o backup é de um instante anterior —
mas nenhuma pode vir **zero** se a produção tem dado. Uma tabela zerada com as outras cheias é o
achado que este teste existe para pegar.

### 3.3 — Um mandato inteiro atravessou?

```sql
with alvo as (select id, nome from caso order by criado_em desc limit 1)
select
  alvo.nome,
  count(distinct d.id)              as documentos,
  count(distinct dv.id)             as versoes,
  count(ce.id)                      as campos,
  count(distinct p.id)              as pendencias
from alvo
left join documento d        on d.caso_id = alvo.id
left join documento_versao dv on dv.documento_id = d.id
left join campo_extraido ce   on ce.documento_versao_id = dv.id
left join pendencia p         on p.caso_id = alvo.id
group by alvo.nome;
```

Documento **e** extração **e** trilha juntos — é isso que a especificação §3 pede no passo 3. Um
mandato com documentos e zero campos extraídos significa que voltou a casca sem o conteúdo.

### 3.4 — O que o n8n chama ainda resolve?

```sql
-- cole o conteúdo de Supabase/conferir/conferir_chamadas.sql
```

Tem que dizer `PODE RODAR`. Prova que o banco restaurado não é só consultável — é **operável**.

**Pare o cronômetro quando 3.1 a 3.4 responderem.**

---

## Parte 4 — o registro (é isto que fica)

Preencha e commite. Sem esta parte, o teste vira lembrança.

```
TESTE DE RESTAURAÇÃO — ____/____/______

Região do projeto:        ______________________
Plano:                    ______________________
Retenção de backup:       ______________________
PITR ligado?              ( ) sim, desde ______  ( ) não

Caminho usado:            ( ) download do dump   ( ) restore gerenciado/PITR
Backup restaurado, de:    ____/____/______ __:__

TEMPO ATÉ O BANCO RESPONDER: ______ minutos

3.1 sonda .............. ( ) zero linhas   ( ) faltaram: ______________
3.2 contagens .......... ( ) nenhuma zerada  ( ) zerou: ______________
3.3 mandato inteiro .... ( ) doc+extração+trilha  ( ) faltou: __________
3.4 PODE RODAR ......... ( ) sim   ( ) não: ______________

O QUE EU DIRIA A UM CLIENTE: "em caso de perda, voltamos em ____ minutos,
com perda máxima de ____ (a distância entre backups)."

Projeto descartável apagado depois?  ( ) sim
```

---

## O que este teste NÃO prova

Dito aqui para ninguém concluir demais dele — é a mesma disciplina do `ACEITE.md`:

- **Não prova o Storage.** As consultas acima leem o Postgres. O **arquivo original** (o PDF) mora
  no Storage, que tem política própria de backup (§3, `[A CONFIRMAR]`). Um restore verde aqui com o
  bucket perdido significa **dado extraído sem documento de origem** — e a proveniência da `0125`
  aponta para um arquivo que não existe mais. Se o console não responder sobre backup de bucket,
  isso é uma pergunta aberta, não um item verde.
- **Não prova o n8n.** O estado de execução do workflow não está no Postgres.
- **Não é um teste de carga.** O tempo medido é de um restore sem ninguém usando o sistema.
