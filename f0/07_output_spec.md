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

**Critério de pronto (DoD):** ✅ dois modos de entrega definidos; ✅ schema-alvo com ordem de
prioridade; ✅ proveniência por célula especificada; ✅ regra anti-ancoragem reafirmada.
*(Layout fino do Excel e da tela do portal a refinar na F2, quando houver dado real fluindo.)*