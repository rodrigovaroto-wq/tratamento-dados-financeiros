# F2 diagnóstico: camada de reconciliação conclui entre 0% e 40% — não verificada antes de acrescentar exigência

**Sessão:** 99 (22/09/2026)  
**Medição:** 21/09/2026 contra produção (banco em `0181`)  
**Status:** ✅ MEDIDO, VEREDICTO CONTRA ROADMAP  
**Impacto:** Bloqueia F2 em forma como foi desenhada

## O achado

**Medição honesta: camada de reconciliação conclui pouco, por caso × entidade (ela concluiu em algum período?)**

| Checagem | Pares caso×ent | Concluiu | Nunca | % |
|---|---|---|---|---|
| `caixa_bp_vs_fluxo` | 33 | **0** | 33 | **0,0%** |
| `mutuos_planilha_vs_balanco` | 12 | 1 | 11 | **8,3%** |
| `caixa_bp_fluxo` | 163 | 14 | 149 | **8,6%** |
| `despfin_dre_vs_divida` | 109 | 15 | 94 | **13,8%** |
| `receita_dre_vs_faturamento` | 109 | 23 | 86 | **21,1%** |
| `intragrupo_espelho` | 12 | 4 | 8 | **33,3%** |
| `ativo_passivo_pl` | 196 | 112 | 84 | **57,1%** |
| `secao_fecha` | 118 | 80 | 38 | **67,8%** |
| `duplicidade_de_rotulo` · `conflito_entre_documentos` | 221 | todos | 0 | **100%** |

**Implicação:** a F2 acrescenta exigência NOVA a uma camada que conclui entre 0% e 40%. Sem diagnóstico do por quê, é construir em andar não verificado.

## A causa-raiz que bloqueia diagnóstico

`precondicao_nao_satisfeita` confunde **4 estados diferentes com remédios opostos** — `fonte_a`/`fonte_b` NULAS em 1.922/1.926 linhas:

1. **Contraparte não existe no caso** (medido: ~278 pares — a checagem rodou onde não havia o que conferir; despachante decide pelo TIPO do documento que chegou, sem saber se o outro lado existe)
2. **Linha não foi localizada** — que pode ser defeito nosso (localizador, versão do extrator) **ou** ausência legítima (DRE que publica resultado LÍQUIDO em vez de despesa bruta)
3. **Unidade divergente** entre os dois lados
4. **Período sem par**

**Fila não é acionável:** descobrir o motivo real exige sessão de investigação forense. Isto é a **regra 1 no diagnóstico do próprio sistema** — ausência declarada sem motivo e sem efeito.

## Achado específico: `despfin_dre_vs_divida` (10,2% conclusão)

Das 81 pendências `linha_exigida_ausente` abertas em produção **antes desta medição**:
- **52 (64%)** são **`DRE / despesa_financeira`** em 10 casos, uma por entidade

| Causa | Entidades |
|---|---|
| **A** — DRE traz `Resultado financeiro líquido` em vez de despesa BRUTA (ausência real, legítima) | **50** |
| **B** — Entidade não tem nenhuma linha financeira | 2 |
| **C** — FALSA: entidade tem `JUROS E COMISSÕES` mas localizador exige "juros" **E** "encargos" no mesmo rótulo | 1 |

**254 de 283 pares de `despfin_dre_vs_divida` não concluem; fila só mostrava 52** — a fila subestima em **5×** porque:
- Pendência é granulada por caso × entidade (52)
- Reconciliação é por caso × entidade × período (254)

**A causa A não é bug:** um DRE pode publicar resultado financeiro LÍQUIDO. A linha exigida não existe — pendência está tecnicamente certa. **O problema é o que ELA DIZ:** "linha 'Despesa Financeira' não foi localizada" lê-se como falha de extração, quando o recado útil seria *"DRE traz resultado líquido; conferência contra mapa de dívida precisa da despesa BRUTA — peça a abertura".*

Isto é a **regra 1 pelo avesso**: ausência REAL com motivo e EFEITO omitidos.

## Correção de método no próprio diagnóstico (22/09)

A medição anterior (20/09) dizia por **período**, não por **caso × entidade**. O despachante roda cada checagem em laço e para no primeiro período que conclui — um caso com 2023 falho e 2024 sucesso gravava FALHA e SUCESSO, e a métrica por período contava como "nunca concluiu".

**Fica registrado nos DOIS formatos de propósito:** quem citar o número tem de dizer qual dos dois está citando. Primeira medição (por período) superestimava — ativo_passivo_pl dizia 29,9%, honesto é 57,1%; secao_fecha dizia 39,3%, honesto é 67,8%.

## Achados que o próprio número abre

- **`caixa_bp_vs_fluxo` com 0 de 33 pares**: ou é checagem que nunca funcionou, ou é nome ANTIGO convivendo com `caixa_bp_fluxo` (que roda 460 pares com 8,6%). **Estágio que nunca concluiu tem exatamente a aparência de estágio que concluiu e não achou nada** — a regra 7 em pessoa.
- **Suspeita NÃO investigada:** `MUTUOS` e `FAT_INTRAGRUPO` (exigências `proposta` da `0113` em produção desde então) também reprovam contra fixture. Pode ser o mesmo defeito de `0185` (termo na `secao`, localizador na `chave`), mais antigo.

## O que fica ABERTO

- **Diagnóstico estrutural:** por que as checagens atuais não concluem? Precisão de exigência não resolve — é investigação forense que falta.
- **As 52 pendências de `despesa_financeira`:** correção não é fazer checagem passar — é pendência DIZER que DRE veio líquido, mapa de dívida precisa da abertura bruta.
- **Decisão de prioridade:** a F2 como desenhada acrescenta exigência NOVA a camada que não é verificada. Decidir se investir em diagnóstico antes ou depois.

## Toca

- Nenhum — é medição pura

## Prova

Consulta contra produção (somente leitura):
```sql
select x.tipo_reconciliacao, count(distinct x.caso_id, x.entidade_id) as pares,
       count(distinct case when x.precondicoes_ok then x.caso_id, x.entidade_id end) as concluiu,
       round(100.0 * count(distinct case when x.precondicoes_ok then x.caso_id, x.entidade_id end) 
             / count(distinct x.caso_id, x.entidade_id), 1) as pct
  from reconciliacao x
 group by x.tipo_reconciliacao
 order by pct
```

**Âncora:** não há linha de código que esta ficha descreva — é medição pura contra banco. Fica válida enquanto `reconciliacao` existir e o despachante não mudar de `exit when <> precondicao_nao_satisfeita`.
