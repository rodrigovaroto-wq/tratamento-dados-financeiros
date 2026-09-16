# ADR-02 — Toda aritmética que produz número para o cliente mora no MOTOR

| | |
|---|---|
| **Estado** | ACEITA em 16/09/2026 (F0, fatia 0.6). A fronteira motor×planilha, aberta na primeira versão, foi **DECIDIDA pelo dono no mesmo dia** — leitura (a), abaixo |
| **Origem** | `ARQUITETURA_ALVO_E_ROADMAP.md`, camada L5 (motor de cálculo, F7) |
| **Governa** | F1 a F17, e principalmente F7 |

## A decisão

**Um número que chega ao cliente tem UM lugar onde é calculado.** Soma, subtração, razão,
projeção, consolidação e eliminação intragrupo pertencem ao motor — não ao nó do n8n, não à tela,
não ao script de export, não a uma fórmula escrita à mão em três lugares que precisam concordar.

O motor é auditável: dado o mesmo insumo, ele devolve o mesmo número, e diz de onde ele veio.

## Por que

Aritmética duplicada não diverge com alarme: diverge com **dois números plausíveis**. O projeto
já tem a versão disso em pequena escala — o `COUNT` posicional que um invariante antigo travava
como mecanismo, e as fixtures que "se comparam entre si": desincronizar uma faz as outras duas
mentirem sobre a terceira. Em números financeiros o custo é outro: o arquivo é auditado por quem
decide sobre a empresa.

## Estado de conformidade hoje — MEDIDO em 16/09/2026

A aritmética mora, HOJE, em **quatro casas**. A primeira contagem que fiz aqui dizia "~10 libs do
portal" e veio de um `grep` frouxo que casava `types.ts` e `rotulos.ts` — corrigida arquivo a
arquivo antes de este documento ser commitado, porque ADR com número inflado desmoraliza a
restrição que ela impõe:

| Casa | Medida |
|---|---|
| n8n (JS) | `N8N/lib/aritmetica.mjs`, 191 linhas |
| SQL | **44** arquivos de migration com `sum(`/soma direta · **15** funções `fn_reconciliar_*` |
| portal (TS) | `modelo-institucional.ts` **9** linhas com aritmética · `premissas-do-realizado.ts` **3** · `export.ts` **3** · `limite-de-envio.ts` **2** (contagem de linhas com operador ou `reduce`, não de operações — é um piso, não um total) |
| Excel entregue | **30** pontos de fórmula gerados por `export.ts` |

Ou seja: **o sistema de hoje não cumpre esta ADR**, e o roadmap sabe disso — o motor é F7. Esta
ADR é a restrição que impede a quinta casa de nascer enquanto ele não existe.

## A fronteira motor × planilha — DECIDIDA pelo dono em 16/09/2026

A quarta casa é diferente das outras três, e a diferença é doutrina escrita:
**"a planilha tem de continuar viva: fórmula lendo a aba Macro, nunca valor escrito"**. O cliente
mexe nas premissas e o modelo responde — é o produto, não um atalho. Então "toda aritmética no
motor" e "planilha viva" só conviviam sob duas leituras possíveis, e a escolha era do dono:

- **(a) o motor calcula, a planilha recalcula o mesmo** — a fórmula do Excel é uma *reimplementação
  declarada* do motor, e algum portão tem de provar que as duas concordam sobre o mesmo insumo;
- ~~(b) a planilha é o motor do que é interativo~~ — descartada.

**Escolhida a leitura (a): "o sistema deve verificar, não duplicar."** A fórmula do Excel
continua existindo — é o produto, o cliente mexe na premissa e vê o modelo responder — mas ela
NUNCA é a fonte da verdade do número. O motor calcula; a fórmula reimplementa o mesmo cálculo
para ficar interativa; e um portão roda os dois sobre o mesmo insumo e **reprova se divergirem**.

**O que isso obriga, e que ainda não existe (é conteúdo de F7, não desta ADR):**
1. o motor (quando existir) expõe uma função por número que a planilha também calcula;
2. o portão de concordância gera o book, lê o valor que a fórmula do Excel produziu (via
   avaliação da planilha, não por inspeção da fórmula em texto) e compara com o que o motor
   calculou para o MESMO insumo;
3. divergência é FALHA do portão, nunca "diferença aceitável" — a régua é `avaliarCelula`, que
   já existe em `portal/scripts/` para outro propósito, com a limitação conhecida de não
   seguir referência entre abas (`.claude/memory/avaliarcelula-nao-cruza-abas.md`);
4. até o motor existir (F7), esta obrigação fica registrada aqui e não é medível — nada no
   portal hoje calcula fora da fórmula para comparar contra ela.

## O que isto proíbe desde já

- número novo calculado em nó Code do n8n quando já existe função SQL que o calcula (e vice-versa);
- total gravado sem as componentes que o formam;
- somar um total junto com as componentes que ele já inclui — a lente "fidelidade do número" do
  `/revisar` existe para isso;
- premissa ausente virando zero em qualquer casa. Célula em branco + nota com o motivo **e o
  efeito** (regra 1).
