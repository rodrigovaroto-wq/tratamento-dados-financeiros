---
name: grupo-por-controle-comum-sem-holding
description: o mandato real não tem holding — as 8 empresas são irmãs sob controle comum de pessoas físicas, e o modelo de participação da 0181 (controladora_id entre EMPRESAS) não tem onde registrar esse vínculo
metadata:
  type: architecture
tipo: achado-de-dado-real
toca:
  - Supabase/migrations/0181_o_controle_que_a_entidade_nunca_registrava.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
---

**MEDIDO em 18/09/2026**, contra os contratos sociais reais do mandato "AMO teste 00"
(caso `1be52ab4-9692-4e17-b332-1dc05dcc8c70`), lendo `campo_extraido` dos documentos
`tipo_taxonomia = 'CONTRATO_SOCIAL'`:

| Empresa | Sócios medidos no contrato |
|---|---|
| GENERAL BUSINESS CENTER | Karina Souto Damasio Tascino 1.677.578 + Rafael Teles 1.677.577 (de 3.355.155 quotas) |
| GENERAL TABACO | Igor Souto Damasio, 10.000 de 10.000 quotas |
| GLOBAL STORE | Rafael Teles, 1.000.000 de 1.000.000 quotas |
| OMNIBEAUTY MARCAS | Igor Souto Damasio 60% · Leandro Morales Lima 20% · Roney Thiago Costa 20% |

**Todos os sócios são PESSOAS FÍSICAS. Nenhuma empresa do grupo é sócia de outra.** Não há
holding. O que liga as 8 empresas é o CONTROLE COMUM das mesmas pessoas — um vínculo que não
passa por dentro de nenhuma delas.

## Por que isso importa para quem for mexer na F1.5

A `0181` modela participação como `entidade.controladora_id` — uma FK de EMPRESA para EMPRESA.
Nesta estrutura real, essa coluna fica **corretamente NULL nas 8 entidades**, e o sistema
**não tem onde registrar que elas formam um grupo**. O modelo não está errado (serve a mandatos
com holding); ele tem um **ponto cego para a forma mais comum do middle market brasileiro**.

A armadilha específica, e é a regra 7 de novo: `controladora_id` vazio aqui é
indistinguível de "ninguém preencheu ainda". Quem olhar o banco depois não consegue separar
"não tem controladora porque o grupo é horizontal" de "tem, mas ninguém cadastrou".

## O que NÃO está medido (regra 1)

- **2 dos 6 contratos vieram com ZERO campos extraídos**: `Certidão 5ª Alteração - AMOBELEZA.pdf`
  e `Certidão 4ª Alteração - CORPORATE.pdf`. Os dois já têm `extracao_falhou` aberta, e o da
  AMOBELEZA também tem `tipo_incorreto` dizendo que o conteúdo é certidão, não contrato — o
  sistema detectou sozinho, antes de qualquer sessão perguntar. **Certidão de Junta não traz
  distribuição de quotas; contrato (alteração consolidada) traz.** Contraexemplo que impede a
  regra fácil: `Certidão 5ª alteração - OMNIBEAUTY.pdf` **extraiu 54 campos** — é certidão de
  inteiro teor. "Certidão" no nome não prevê o resultado.
- **2 das 8 entidades não têm contrato social nenhum** (OMNIBEAUTY DISTRIBUIDORA PR e RS).
  Pendências `item_faltante` abertas nesta rodada, motivo `contrato_social_ausente:<entidade_id>`.
- Logo: estrutura societária medida em **4 de 8** entidades. As outras 4 seguem desconhecidas.

## E por que o COMBINADO do cliente provavelmente não existe

"Demonstração **combinada**" é a forma contábil usada justamente quando as empresas estão sob
controle comum **sem controladora** — é o caso aqui. Diferente do consolidado de um grupo com
holding, ela não é exigida em formato padrão, então um grupo assim frequentemente **nunca
preparou uma**. A ausência do documento não é descuido do cliente: é consequência da forma do
grupo. A fatia 1.6 (aceite financeiro contra o combinado do cliente) presumia que ele existiria.

**Consequência boa:** a `0180` (`perimetro`) atravessa isso intacta — ela registra "estas
empresas entram no combinado" sem exigir hierarquia nenhuma, que é exatamente o conceito que se
aplica a empresas irmãs.
