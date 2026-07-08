# 05 — Classificação Contábil Assistida

> **Nasce em N0 (sombra) no MVP** — registra sugestão, não decide. **Teto N1 para sempre**:
> nunca vira número sem aceite humano. É a área de maior risco interpretativo do sistema.

## Taxonomia fechada sugerida (enum versionado no Supabase)

- `recorrente`
- `nao_recorrente`
- `extraordinario`
- `candidato_ajuste_ebitda`
- `revisar_manual` (default de escape)

A taxonomia é **fechada** e **versionada**: a fonte da verdade é uma tabela no Postgres; o
Obsidian mantém o espelho legível com a justificativa de cada rótulo.

## Quando a sugestão PODE ser aceita (auto-aceite)

Só quando **as três** forem verdade:

1. confiança acima do threshold **daquele campo/tipo de documento**; **e**
2. bate com um **padrão conhecido** (mapeamento de rubrica/keyword pré-registrado); **e**
3. dentro de um tipo de documento onde a **extração já foi medida como confiável**.

Qualquer ambiguidade, qualquer confiança abaixo do threshold, qualquer rubrica nova →
`revisar_manual`. O default é conservador.

## Registro de justificativa (toda sugestão)

```
{ sugestao, taxonomia_id, confianca, justificativa,
  origem (doc / página / linha), regra_ou_modelo, versao_taxonomia }
```

## Registro de override humano

```
{ classificacao_final, autor, timestamp, motivo, sugestao_original }
```

Append-only. O override vira **sinal de calibração**: onde humanos discordam sistematicamente
da máquina, ajusta-se regra/threshold (ou não se sobe o dial daquele estágio).

## Regra anti-ancoragem (inegociável)

A sugestão é **metadado advisory**, nunca um valor que pré-preenche a modelagem. **Nenhum
número entra na base de modelagem sem um evento explícito de aceite humano.** Sem isso, o
sistema induz o analista ao erro da máquina — o que é pior do que não ter sugestão nenhuma.
