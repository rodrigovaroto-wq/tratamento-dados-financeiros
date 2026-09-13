---
name: materialized-nao-e-enfeite
description: sem MATERIALIZED o Postgres inlina a CTE usada uma vez, e o agrupamento escrito para MATAR o produto cartesiano vira o produto cartesiano
metadata:
  type: architecture
tipo: defeito
toca: []
---

`fn_conflitos_do_caso` levava **12,4 s por chamada**: o planner estima `rows=1` numa CTE onde há
2.619, escolhe Nested Loop e compara **6.859.127 pares para achar 34** — vezes as 123 chamadas que
a `0151` dispara.

A correção foi agrupar. **E ela não acontecia sem `MATERIALIZED`:** a versão agrupada sem a
palavra foi medida em **12.068 ms**, praticamente o original. O Postgres inlina CTE usada uma só
vez, então o agrupamento desaparecia no plano e o cartesiano voltava.

Com `MATERIALIZED`: **1.790 ms**, as mesmas 34 linhas. Medido em produção, não estimado.

A lição generaliza: neste banco, uma otimização de CTE que não força a materialização pode ser
apagada pelo planner sem nada acusar — e o sintoma é a ausência de melhora, que é fácil atribuir
a "então não era isso". **Meça o depois, não só o antes.**
