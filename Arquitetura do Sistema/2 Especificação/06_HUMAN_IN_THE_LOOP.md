# 06 — Human-in-the-loop

## Checkpoints

- **Portão 1 (Completude):** leve, pode ser assíncrono/automático. Humano só olha exceções.
- **Portão 2 (Aprovação de avanço):** pesado, obrigatório, sênior, auditado. Nenhum caso
  avança para análise sem ele.

## Papéis e responsabilidades

| Papel | Responsabilidade | Pode |
|---|---|---|
| **Analista** | Revisar extração e pendências, corrigir, solicitar reenvio | Resolver pendência, disparar reenvio |
| **Revisor sênior / gerente** | Aprovar avanço, override de classificação | Fechar Portão 2, autorizar "aceitar com ressalva" |
| **Cliente** (fase futura) | Enviar/reenviar informação | Ver status e pendências próprias |

## Como evitar que a fila exploda (gargalo nº 1)

1. **Auto-clear determinístico** de itens objetivos de alta confiança (não vão para a fila).
2. **Revisão em lote**, não item a item.
3. Roteia para humano **só o que está abaixo do threshold ou flagado**.
4. **SLA + aging** de pendências; priorização por severidade e por bloqueio de caso.
5. Métrica de saúde: **% do volume que exigiu toque humano** — se subir, recalibrar.

## Calibração de thresholds (e por que confiança de LLM não basta)

**Confiança de LLM não é probabilidade calibrada.** No `clipping-news`, o threshold é sobre
distância de cosseno (métrica real que transfere para um número). Aqui, a "confiança" que um
LLM se autoatribui na classificação é muito mais mole. Regra:

- Começar conservador (N0/N1 — mais revisão humana).
- **Logar todo override.**
- Medir periodicamente a **concordância humano-vs-máquina** contra o golden set.
- **Subir o dial de um estágio só onde a concordância for consistentemente alta.**
- **Nunca subir autonomia sem golden set.** Toda subida é reversível.

## Auditoria

Log de eventos **append-only** (quem / o quê / quando / por quê) + tabela de decisões
imutável. Toda passagem de portão, todo override e toda mudança de dial de autonomia geram
evento. A auditabilidade **é** parte do produto, não enfeite.
