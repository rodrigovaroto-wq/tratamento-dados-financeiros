# 0.7 — Especificação do Output para o Analista  ·  [DECISÃO v0]

**Objetivo:** definir concretamente **o que o analista recebe** quando o sistema termina de
tratar um caso. Este artefato preenche a lacuna apontada pelo próprio projeto:

> *"'Preparação de base para modelagem' sem schema-alvo é caixa vazia; é consequência."*
> — `docs/00_VISAO_E_ESCOPO.md`

O output é **o núcleo de valor do projeto** (facilitar o trabalho do analista e a curadoria dos
dados financeiros do cliente), e até esta versão nunca havia sido especificado. Definido por
Rodrigo Varoto (dono) em 2026-07-14. Estado **v0** — o layout fino é refinável.

## Princípio inegociável (anti-ancoragem)

Nenhum número entra na base viva ou no export sem uma `decisao` de **aceite humano** ligada
(ver `docs/05_CLASSIFICACAO_CONTABIL.md` e 0.5). **O output é consequência do Portão 2**, não
paralelo a ele. Dado sem aceite não é entregue como fato — no máximo aparece como *sugestão
pendente de revisão*, visualmente distinta.

## Dois modos de entrega

### Modo A — Base viva no portal (Vercel) · principal
O analista acessa o portal e **consulta/filtra** os dados curados na tela, por:
- **Entidade** (empresa do grupo) × **Período** × **Conta/linha financeira**.
- Visão consolidada do caso e visão por entidade.

Cada valor exibido carrega sua **proveniência** (ver abaixo) e seu **status de aceite**
(aceito / pendente / com ressalva). É a fonte viva — reflete o estado atual do caso em tempo
real (Realtime do Supabase).

### Modo B — Export para Excel · sob demanda
Botão que gera uma **planilha padronizada**, **uma aba por demonstração**, consolidando
**entidades × períodos**, pronta para o analista levar ao modelo dele. O export é um *snapshot*
do que está aceito no momento da geração (com data-base e versão da taxonomia registradas).

## Schema-alvo do output (ordem de prioridade — travada)

A ordem reflete o que tem mais valor tratar primeiro (decisão 0.2/planejamento):

1. **Demonstrações (Balanço / DRE / DFC / Combinado)** — linhas contábeis consolidadas por
   **entidade × período**. É a espinha dorsal. Aba(s): `Balanço`, `DRE`, `Fluxo de Caixa`,
   `Combinado`.
2. **Faturamento / receita** — série **mensal por entidade** (base: `FATURAMENTO_24M`). Aba:
   `Faturamento`.
3. **Mapa de dívida** — credor, modalidade, saldo, taxa, vencimento, garantias. Aba:
   `Dívida`. *(Consolidado a partir de `MUTUOS` + itens variáveis de dívida quando presentes.)*
4. **Fluxo de caixa (realizado / projetado)** — série por período. Aba: `Fluxo Projetado`
   quando disponível.

> Itens 3 e 4 dependem de documentos que podem estar no nível **Variável** da taxonomia (0.3);
> aparecem no output **quando presentes e aceitos**, sem bloquear a entrega dos itens 1 e 2.

## Proveniência por célula (o que diferencia de "copiar do PDF")

Todo número entregue — na base viva e no export — é rastreável até a origem:

| Campo | Descrição |
|---|---|
| `valor` | O número curado |
| `documento_versao_origem` | Qual arquivo/versão gerou o dado (liga a `campo_extraido`, 0.5) |
| `origem_detalhe` | Página / linha / célula de origem |
| `confianca` | Score da extração |
| `status_aceite` | aceito / pendente / com ressalva |
| `aceito_por` / `aceito_em` | Quem deu o aceite (Portão 2) e quando |
| `versao_taxonomia` | Versão da taxonomia usada (rastreabilidade) |

No Excel, a proveniência pode ir em coluna(s) auxiliar(es) ou em comentário de célula; no
portal, aparece ao passar o mouse / abrir o detalhe do valor.

## Fora do escopo (reforço)

O output **não** é modelagem financeira, **não** projeta, **não** decide classificação
contábil como fato (a classificação `recorrente/não-recorrente/...` viaja como **metadado
advisory**, nunca pré-preenchendo o modelo). O sistema **habilita** o analista com dado
confiável e rastreável — não o substitui.

> **Emenda 2026-07-22 (dono):** subtotais/totais por seção passam a aparecer no export como
> **fórmulas Excel** (`=SUM(...)`), colocadas no cabeçalho de cada seção/grupo do Balanço/DRE/
> Fluxo de Caixa. Isso NÃO é modelagem nem invenção de número: a fórmula é transparente e
> auditável (o analista vê exatamente o que está sendo somado) e opera só sobre as linhas
> extraídas. O total que o **próprio documento** trouxer continua preservado, numa linha de
> conferência ao lado da fórmula; se a soma calculada divergir do informado, ambos são
> sinalizados (vira uma checagem de reconciliação embutida). A anti-ancoragem segue valendo para
> os DADOS extraídos: nenhum valor de conta vira fato sem aceite humano. Detalhe da implementação:
> `portal/src/lib/statement-templates.ts` (estrutura CPC/Lei 6.404) + `portal/src/lib/export.ts`.

> **Emenda 2026-07-24 (dono):** o export passa a entregar também a camada de **leitura analítica**
> que um analista de RX/M&A espera pronta — **análise vertical (AV%, common-size)**, **análise
> horizontal (Δ% entre períodos comparáveis)** e um bloco de **indicadores de liquidez/estrutura**
> no Balanço. Isso NÃO é modelagem nem projeção: são razões entre números **já extraídos**,
> calculadas por fórmula Excel transparente (`IFERROR`), e **nenhum índice é emitido sem o insumo
> real** (faltando a linha, a célula fica vazia — nunca estimada). A anti-ancoragem segue: %s e
> índices referenciam células que continuam PENDENTES até o aceite humano. Fundamentação e
> faseamento do que ainda falta (índices que exigem detalhamento de conta) em
> `f0/08_padrao_entrega_analitica.md`.

**Critério de pronto (DoD):** ✅ dois modos de entrega definidos; ✅ schema-alvo com ordem de
prioridade; ✅ proveniência por célula especificada; ✅ regra anti-ancoragem reafirmada.
*(Layout fino do Excel e da tela do portal a refinar na F2, quando houver dado real fluindo.)*

---

## Emenda (teste v25) — o total da seção é o que o DOCUMENTO informou

Achado no teste v25: **36 de 44 somas do Balanço divergiam do total informado**, várias exatamente
2,00x. Causa: demonstração real é hierárquica e imprime subtotais de subseção ("Disponível" acima de
"Caixa e bancos" + "Aplicações financeiras"); a soma da seção contava o subtotal **e** os seus
componentes. A detecção estrutural do subtotal (`detectarSubtotaisInformados`) resolve quando a IA
anota a SUBSEÇÃO em `campo_extraido.secao` — mas quando ela anota a seção de topo, ou quando o mesmo
rótulo é subtotal num documento e conta-folha em outro (o export junta os dois na mesma linha), o
subtotal passa e o total sai dobrado. Isso contaminava AV%, Δ% e todos os indicadores.

**Regra a partir daqui:** quando o documento traz o total de uma seção, **ele é o número da seção**.
O cabeçalho da seção aponta para a célula do valor extraído (fórmula `=<célula>`, não valor colado —
a planilha continua viva e a proveniência fica a um clique), e a **nossa** soma vira uma linha de
checagem logo abaixo (`↳ soma das contas listadas (checagem)` / `↳ soma das seções acima (checagem)`).
Quando as duas divergem, a linha do informado é pintada e a nota explica a causa provável.

Três consequências que valem registrar:

1. **O total deixa de depender de acertarmos a hierarquia.** Errar a detecção de subtotal passa a ser
   um ruído visível numa linha de checagem, não um total silenciosamente errado.
2. **É mais fiel ao princípio de anti-ancoragem** (`docs/01`): o número autoritativo é o que o
   documento disse; o que nós calculamos fica ao lado, identificado como cálculo nosso.
3. **A divergência continua sendo o sinal útil** — não é escondida, é justamente o que fica destacado.

Só quando o documento **não** informa o total daquela coluna a seção volta a ser `=SUM(range)`.

### Seção declarada pelo documento manda na classificação

Junto: quando `campo_extraido.secao` nomeia uma subseção **inequívoca** da estrutura ("Realizável a
Longo Prazo", "Investimentos", "Imobilizado", "Intangível", "Disponível", "Estoques", "Obrigações
Tributárias"…), ela é autoritativa para a colocação da conta. Antes, só seções que diziam
"ativo"/"passivo"/"patrimônio líquido" contavam, e um cabeçalho de subseção caía no passe de
palavras-chave do rótulo — onde o vocabulário podia mandar a conta para o lugar errado:
`secao="Realizável a Longo Prazo"` + `chave="Títulos a receber - venda de imobilizado"` ia para
Imobilizado; `secao="Investimentos"` + `chave="Mútuos a receber de controladas"` ia para o Ativo
Circulante; `secao="Imobilizado"` + `chave="Terrenos"` caía em Não Classificadas.

Ficam **de fora** da lista, de propósito, os cabeçalhos que existem nos dois lados do balanço —
"Fornecedores", "Empréstimos e Financiamentos", "Partes Relacionadas", "Provisões". Chutar o lado
deles distorceria liquidez e endividamento; eles continuam decididos pelo rótulo + consenso de irmãos.
