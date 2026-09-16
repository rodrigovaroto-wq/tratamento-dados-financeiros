# ADR-01 — A evidência é imutável; o canônico é construído ACIMA dela

| | |
|---|---|
| **Estado** | ACEITA em 16/09/2026 (F0, fatia 0.6) |
| **Origem** | `ARQUITETURA_ALVO_E_ROADMAP.md`, camadas L1→L3 — esta ADR registra a decisão, não a inventa |
| **Governa** | F1 a F17. Nenhuma fase pode contrariá-la sem revogá-la aqui, por escrito |

## A decisão

**O que foi extraído de um documento nunca é corrigido no lugar.** `campo_extraido` guarda o
valor **como veio** — com o rótulo original, a página, a confiança, a moeda e a unidade
declaradas. Correção, normalização, desambiguação e consolidação produzem registro **NOVO**, numa
camada acima, que aponta para a evidência de origem.

Em uma frase: **a evidência é append-only; o canônico é derivado e refazível.**

## Por que, e o número que decidiu

Na v48, **20 das 27 pendências eram falsas**: a extração estava certa e quem errava eram as
checagens. Se a correção tivesse sido aplicada *sobre* `campo_extraido`, cada uma daquelas 20
teria destruído o dado certo para acomodar uma checagem errada — e não haveria como descobrir,
porque o valor original não existiria mais.

É a mesma razão pela qual `.claude/memory/nunca-corrigir-funcao-por-replace.md` existe do lado do
código: **o que se perde em silêncio não volta.** Aqui o custo é maior: o dado é do cliente, e o
arquivo entregue é auditado por quem decide.

## O que isto proíbe, explicitamente

- `UPDATE` em `campo_extraido` para "arrumar" valor, rótulo, moeda ou unidade;
- reprocessar um documento sobrescrevendo a extração anterior em vez de versioná-la;
- consolidar somando linhas e guardando só o total, sem as componentes e sem o vínculo;
- qualquer "limpeza" que deixe o banco sem como responder *de onde veio este número*.

## O que isto NÃO proíbe

- criar camada canônica acima (`conta_canonica`, `fato_financeiro`), que é justamente o desenho;
- marcar evidência como superada (`documento_versao`, restatement) — **marcar não é apagar**;
- apagar dado por pedido do cliente. Isso é exclusão deliberada e rastreável, não correção.

## Estado de conformidade hoje — MEDIDO, não suposto

A camada L1 existe (`campo_extraido`, `documento_fato`, `documento_versao`) e as camadas L2/L3
que a ADR pressupõe **ainda não**: estão marcadas `[NOVO]` no roadmap e são o conteúdo de F1–F4.
Portanto esta ADR é hoje **uma restrição sobre o que virá**, e não a descrição de um sistema que
já a cumpre inteira. Declará-la cumprida seria a mesma classe de defeito que ela existe para
evitar.

**Quem descumprir esta ADR não produz erro nenhum** — produz um banco que responde a pergunta
errada com confiança. Por isso a revisão deste projeto pergunta, para todo diff que toca banco:
*esta mudança destrói alguma evidência para acomodar uma conclusão?*
