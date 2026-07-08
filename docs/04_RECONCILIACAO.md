# 04 — Reconciliação Cruzada

## Tese central

Reconciliação **não é um problema único**; são três problemas com níveis de automação
radicalmente diferentes. Tratar tudo como "threshold" é o erro que a v1 do plano original
cometia. Além disso, **toda reconciliação só roda se suas pré-condições
(período/entidade/escopo/moeda) baterem**; senão, vira pendência — não resultado falso-limpo.

## As três classes

| Classe | Exemplos | Autonomia (teto) | Comportamento |
|---|---|---|---|
| **A — Aritmética / identidade** | Ativo = Passivo + PL; caixa no BP vs saldo final do fluxo; soma das parcelas vs saldo total do mapa de dívida | N1 → N2 | Com pré-condições OK e tolerância: divergência acima da tolerância → **pendência automática** |
| **B — Semi-objetiva (agregação/período)** | Receita da DRE vs soma do faturamento mensal; despesa financeira vs juros do mapa de dívida | **N1** | **Banda de materialidade** → sempre revisão na zona cinzenta |
| **C — Interpretativa (mapeamento/julgamento)** | Mapa de dívida vs balanço; mútuos/intragrupo; garantias vs docs pessoais dos sócios; contrato social vs organograma | **N1** | **Não reconcilia** — *aproxima para humano*: mostra as duas fontes, humano decide |

> A maioria dos exemplos originais é **Classe C**: plano de contas não bate, períodos não
> batem, entidades diferem, rubricas têm nomes diferentes. Isso é julgamento, não threshold.

## Regras e materialidade

- **Materialidade** = **piso absoluto em R$** (ex.: R$ 50k) **E** **percentual relativo a uma
  base** (ex.: 2% do ativo/dívida total) **E** **tier de risco da conta**. Divergência só é
  "material" se cruzar os critérios definidos **por tipo de reconciliação** — não um threshold
  único. (Lição direta do `clipping-news`: threshold não transfere entre contextos.)
- **Thresholds por tipo de reconciliação**, calibrados começando conservadores.
- **Pré-condições explícitas** por reconciliação: mesmo período, mesma entidade, mesmo escopo
  de consolidação, mesma moeda. Não satisfeitas → pendência, reconciliação não roda.

## O que é automático vs revisão

- **Automático (teto N2):** apenas **Classe A** (identidades aritméticas puras) com
  pré-condições satisfeitas.
- **Revisão:** toda a **Classe B** na banda cinzenta e **toda** a **Classe C**.
- **Papel do LLM:** só como **hipótese explicativa** de uma divergência **já detectada
  deterministicamente** (ex.: "possível causa: reclassificação entre curto/longo prazo") —
  **nunca** para decidir se reconciliou.

## Evolução

- No MVP, Classe A opera em N1 (sugestão de pendência confirmada por humano). Sobe para N2
  apenas quando a taxa de falso-positivo medida for baixa.
- Classe B permanece em N1. Classe C permanece em N1 (aproximação) — **não vira automação**.
