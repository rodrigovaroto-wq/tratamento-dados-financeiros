# -*- coding: utf-8 -*-
import motor as M, demonstracoes as X, render as R

bp, tot = M.construir()
l25, v24, alvo = X.dre_metalurgica(tot)
c25, prejuizo = X.cascata(l25)
receita_bruta = sum(v for r, v, t in c25 if t == "conta" and r.startswith(("Vendas", "Prestação")))
desp_fin = [v for r, v, t in c25 if r.startswith("(-) Despesas financeiras")][0]
fat, t24f, t25f = X.faturamento_24m(receita_bruta)
contratos = X.mapa_divida(desp_fin)
mut, tot_mut = X.mutuos_intragrupo(tot)

feitos = []
feitos.append(R.pdf_balanco("metalurgica", bp, tot, "01_BP_Vertentes_Metalurgica_2025x2024.pdf",
    nota_extra="Nota 2 — Reclassificação: em razão do descumprimento de cláusula restritiva (covenant) de "
               "cobertura de juros no contrato com o Banco Meridional S.A., parcela de financiamentos "
               "originalmente classificada no passivo não circulante foi reclassificada para o circulante."))
feitos.append(R.pdf_balanco("componentes", bp, tot, "02_BP_Vertentes_Componentes_2025x2024.pdf",
    nota_extra="Nota 1 — A Sociedade apresenta PASSIVO A DESCOBERTO em 31/12/2025. A continuidade das "
               "operações depende de aporte da controladora e da renegociação dos débitos em atraso."))
feitos.append(R.pdf_balanco("holding", bp, tot, "03_BP_Vertentes_Participacoes_2025x2024.pdf",
    nota_extra="Nota 3 — Os investimentos em controladas são avaliados por equivalência patrimonial. O "
               "investimento em controlada com patrimônio líquido negativo é mantido por valor zero, sendo "
               "a parcela excedente registrada como provisão para passivo a descoberto no passivo não circulante."))
feitos.append(R.pdf_balanco("logistica", bp, tot, "04_BP_VT_Logistica_2025x2024.pdf"))
feitos.append(R.pdf_balanco("spe", bp, tot, "05_BP_Vertentes_Imoveis_SPE_2025x2024.pdf"))
feitos.append(R.pdf_combinado(bp, tot, 2025, "06_BP_COMBINADO_Grupo_Vertentes_2025.pdf"))
feitos.append(R.pdf_dre(tot, "07_DRE_Vertentes_Metalurgica_2025x2024.pdf"))
feitos.append(R.pdf_dfc(tot, prejuizo, "08_DFC_Vertentes_Metalurgica_2025.pdf"))
feitos.append(R.pdf_dmpl(tot, prejuizo, "09_DMPL_Vertentes_Metalurgica_2025.pdf"))
feitos.append(R.pdf_faturamento(fat, t24f, t25f, "10_Faturamento_24M_Vertentes_Metalurgica.pdf"))
feitos.append(R.pdf_mapa_divida(contratos, "11_Mapa_Divida_Vertentes_Metalurgica_2025.pdf"))
feitos.append(R.pdf_mutuos(mut, tot_mut, tot, "12_Mutuos_Intragrupo_Grupo_Vertentes_2025.pdf"))
feitos.append(R.pdf_balancete(bp, "13_Balancete_Analitico_Componentes_2025.pdf"))
feitos.append(R.pdf_notas(tot, "14_Notas_Explicativas_Grupo_Vertentes_2025.pdf"))

print(f"{len(feitos)} PDFs gerados:")
for f in feitos: print("  ", f)

# ---------------------------------------------------------------- GABARITO ---
import json
import os

c25c, c24c = M.combinado(bp, tot, 2025), M.combinado(bp, tot, 2024)
anc = {r: v for r, v, t in c25 if t == "ancora"}
t25, t24 = tot[2025]["metalurgica"], tot[2024]["metalurgica"]

gab = {
    "grupo": M.D.GRUPO,
    "entidades": {k: M.D.ENTIDADES[k]["razao_social"] for k in M.D.ENTIDADES},
    "balanco_por_entidade": {
        str(ano): {k: {ch: tot[ano][k][ch] for ch in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL")}
                   for k in ("holding", "metalurgica", "componentes", "logistica", "spe")}
        for ano in (2024, 2025)},
    "combinado": {str(a): {kk: vv for kk, vv in M.combinado(bp, tot, a).items()
                           if kk in ("ativo", "passivo", "pl", "nci", "elim_invest",
                                     "elim_mutuos", "elim_provisao", "pl_holding")}
                  for a in (2024, 2025)},
    "dre_metalurgica_2025": anc,
    "receita_bruta_2025": receita_bruta,
    "prejuizo_2025": prejuizo,
    "faturamento_total": {"2024": t24f, "2025": t25f},
    "divida_total_R$": sum(c[2] for c in contratos) * 1000,
    "juros_exercicio_R$": sum(c[6] for c in contratos) * 1000,
    "despesa_financeira_DRE_R$mil": abs(desp_fin),
    "mutuos_planilha": tot_mut,
    "mutuos_balanco": tot[2025]["_mutuos_holding"] + 1400 + 640,
}
with open(f"{R.OUT}/GABARITO.json", "w", encoding="utf-8") as fh:
    json.dump(gab, fh, indent=2, ensure_ascii=False)


# ------------------------------------------------------------ GUIA DE TESTE --
def f(v):
    return f"{v:,}".replace(",", ".")


def dec(v, n=2):
    return f"{v:.{n}f}".replace(".", ",")


guia = f"""# Book de teste — GRUPO VERTENTES (dados sintéticos)

Grupo industrial fictício **em dificuldade financeira severa**, com 5 empresas sob controle comum.
Todos os documentos são **sintéticos** e trazem essa marcação no rodapé. Nenhum corresponde a
empresa, pessoa ou fato real.

Regenerar: `python3 gerar.py` (requer `reportlab`). Os números são calculados e **validados por
assert** — nenhum total é digitado à mão, e o balanço fecha em todas as entidades e no combinado.

## A história (o que esperar da análise)

Metalmecânica de autopeças que perdeu contratos e entrou em espiral: receita caindo, margem
comprimida, dívida migrando para o curto prazo por **quebra de covenant**, fornecedores e tributos em
atraso, antecipação de recebíveis para fechar o caixa. Uma controlada já está com **passivo a
descoberto**. Os imóveis (SPE) são o que ainda sustenta o patrimônio do grupo.

| Entidade | Papel | PL 2024 -> 2025 (R$ mil) | Situação |
|---|---|---|---|
| Vertentes Participações S.A. | Holding | {f(tot[2024]['holding']['PL'])} -> {f(tot[2025]['holding']['PL'])} | Investimentos por MEP; empréstimo de sócios |
| Vertentes Metalúrgica Ltda. | Operacional principal | {f(t24['PL'])} -> {f(t25['PL'])} | Queimou 72% do PL em um ano |
| Vertentes Componentes Automotivos Ltda. | Operacional | {f(tot[2024]['componentes']['PL'])} -> {f(tot[2025]['componentes']['PL'])} | **Passivo a descoberto** |
| VT Logística e Transportes Ltda. | Serviços (70%) | {f(tot[2024]['logistica']['PL'])} -> {f(tot[2025]['logistica']['PL'])} | Quase zerando o PL |
| Vertentes Imóveis SPE Ltda. | Imobiliária | {f(tot[2024]['spe']['PL'])} -> {f(tot[2025]['spe']['PL'])} | Sustenta o patrimônio |

**Indicadores da Metalúrgica (o que o export deve calcular):** liquidez corrente
{dec(t24['AC']/t24['PC'])} -> **{dec(t25['AC']/t25['PC'])}**; capital circulante líquido
{f(t24['AC']-t24['PC'])} -> **{f(t25['AC']-t25['PC'])}**; margem bruta 2025
**{dec(anc['LUCRO BRUTO']/anc['RECEITA OPERACIONAL LÍQUIDA']*100,1)}%**; EBIT 2025
**{f(anc['RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO'])}** (negativo).

## Os 14 documentos e o que cada um estressa

| # | Documento | O que testa no pipeline |
|---|---|---|
| 01 | BP Metalúrgica 2025x2024 | **Balanço detalhado** (4 níveis, ~60 contas), comparativo -> `periodo_coluna`, Delta%, AV%, subtotais por seção CPC |
| 02 | BP Componentes 2025x2024 | **PL negativo** (passivo a descoberto) — indicadores negativos sem quebrar |
| 03 | BP Participações (holding) | **MEP** e `Provisão para passivo a descoberto` — vocabulário raro |
| 04 | BP VT Logística | Empresa pequena, plano de contas enxuto |
| 05 | BP Imóveis SPE | `Propriedades para investimento` — Investimentos vs Imobilizado |
| 06 | **BP COMBINADO** | **Uma coluna por empresa + Eliminações + Combinado** -> `entidade_coluna`; a coluna "Eliminações" **não é uma empresa** (armadilha) |
| 07 | DRE Metalúrgica 2025x2024 | Cascata completa, deduções, `(-)` nos rótulos, margens |
| 08 | DFC método indireto | Amarra com o Disponível do balanço |
| 09 | DMPL | Linhas "SALDOS EM 31 DE DEZEMBRO DE..." -> a guarda de DMPL deve **excluí-las** do PL |
| 10 | Faturamento 24 meses | Série mensal -> ordenação **cronológica** (jan..dez, não alfabética) |
| 11 | **Mapa de dívida** | **Em REAIS (unidades)**, enquanto o resto está em R$ mil -> pré-condição de **escala** (Classe B) |
| 12 | Mútuos intragrupo | **Divergência deliberada de R$ 180 mil** contra o balanço |
| 13 | Balancete analítico | Colunas **Débito/Crédito** e natureza **D/C** -> convenção de sinal |
| 14 | Notas explicativas | Texto corrido (going concern, covenant) — não deve gerar linhas financeiras falsas |

## Gabarito (confira contra o export)

**Balanço — Metalúrgica (R$ mil)**

| | 2025 | 2024 |
|---|---|---|
| Ativo Circulante | {f(t25['AC'])} | {f(t24['AC'])} |
| Ativo Não Circulante | {f(t25['ANC'])} | {f(t24['ANC'])} |
| **TOTAL DO ATIVO** | **{f(t25['ATIVO'])}** | **{f(t24['ATIVO'])}** |
| Passivo Circulante | {f(t25['PC'])} | {f(t24['PC'])} |
| Passivo Não Circulante | {f(t25['PNC'])} | {f(t24['PNC'])} |
| Patrimônio Líquido | {f(t25['PL'])} | {f(t24['PL'])} |

**Combinado 2025:** Ativo **{f(c25c['ativo'])}** = Passivo {f(c25c['passivo'])} + PL {f(c25c['pl'])}
(holding {f(c25c['pl_holding'])} + não controladores {f(c25c['nci'])}).
Eliminações: investimentos {f(c25c['elim_invest'])}, passivo a descoberto {f(c25c['elim_provisao'])},
intragrupo {f(c25c['elim_mutuos'])}.

**DRE Metalúrgica 2025:** Receita bruta {f(receita_bruta)} · Receita líquida
{f(anc['RECEITA OPERACIONAL LÍQUIDA'])} · Lucro bruto {f(anc['LUCRO BRUTO'])} · EBIT
{f(anc['RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO'])} · **Prejuízo {f(prejuizo)}**

**Amarrações que devem fechar (a reconciliação tem de achar tudo isso):**
- Ativo = Passivo + PL em **todas** as entidades e no combinado.
- Prejuízo da DRE ({f(prejuizo)}) = variação dos prejuízos acumulados na DMPL e no balanço.
- Saldo final de caixa da DFC (**500**) = Disponível do balanço 2025.
- Soma do faturamento mensal de 2025 (**{f(t25f)}**) = Receita Operacional Bruta da DRE.
- Juros do mapa de dívida (**R$ {f(sum(c[6] for c in contratos)*1000)}**, em reais) = Despesas
  financeiras da DRE (**{f(abs(desp_fin))}** em R$ mil) — **escalas diferentes de propósito**.

## Armadilhas deliberadas (é aqui que o sistema deve se provar)

1. **Escalas diferentes entre documentos** — balanço/DRE em R$ mil, mapa de dívida em reais. A Classe B
   deve acusar `precondição não satisfeita` em vez de comparar mil contra unidade.
2. **Coluna "Eliminações" no combinado** — não é uma empresa; se virar coluna de entidade no export,
   a leitura fica errada.
3. **Nomenclatura diferente para a mesma conta** — "Disponibilidades" (Metalúrgica), "Numerário
   Disponível" (Componentes), "Bancos Conta Movimento" (Logística), "Caixa e Equivalentes" (Holding).
4. **Linhas de DMPL** ("SALDOS EM 31 DE DEZEMBRO DE 2024") não podem ser somadas ao PL.
5. **Meses fora de ordem alfabética** no faturamento — a série tem de sair cronológica e o Delta% tem
   de casar meses que se sucedem.
6. **Contas redutoras entre parênteses** (PECLD, depreciação, provisões) -> precisam virar negativo.
7. **Divergência de R$ 180 mil** entre a planilha de mútuos e o balanço — deve aparecer para o humano.
8. **Linhas não monetárias** no faturamento ("Ticket médio por pedido") — não devem herdar a escala.
9. **Balancete com D/C** — a natureza do saldo determina o sinal.
10. **Notas explicativas** são texto corrido — não devem gerar linhas financeiras.
"""
with open(f"{R.OUT}/GUIA_DE_TESTE.md", "w", encoding="utf-8") as fh:
    fh.write(guia)

print("\nGABARITO.json e GUIA_DE_TESTE.md gravados em", R.OUT)

# ------------------------------------------------------------------ MÉTRICAS -
# O mesmo METRICAS.json que o book-canastra escreve, e pelo mesmo motivo: é o
# insumo de `N8N/medir-custo-book.mjs`, que converte páginas/linhas em dólares
# com as funções de orçamento que rodam em produção.
#
# Faltava AQUI, e a falta apareceu do pior jeito: este é o book que o dono
# rodou de verdade (14 documentos, US$ 0,90 de fatura), e era justamente o que
# o medidor não conseguia abrir. Projetar economia sobre o book sintético
# enquanto a fatura vinha do outro é comparar duas coisas diferentes.
import re as _re

import extrai as _extrai

_metricas = []
_texto_por_arquivo = {}
for _arquivo in sorted(os.listdir(R.OUT)):
    if not _arquivo.lower().endswith(".pdf"):
        continue
    _caminho = f"{R.OUT}/{_arquivo}"
    _bruto = open(_caminho, "rb").read()
    # `extrai.texto` daqui devolve LISTA de fragmentos (um por comando de texto do
    # PDF) e a do book-canastra devolve string com um fragmento por linha — as
    # duas descrevem a mesma coisa, então juntar por "\n" iguala a unidade. E a
    # unidade importa: cada fragmento com dígito é uma CÉLULA de valor, que é o
    # que vira token de saída, não uma linha de conta (uma conta comparativa tem
    # uma célula por coluna de período).
    _verdade = R.CONTAGEM.get(_arquivo, {"linhas_de_conta": 0, "celulas_de_valor": 0,
                                         "contas_distintas": 0})
    _bruto_texto = _extrai.texto(_bruto)  # bytes: lido UMA vez, na linha 202
    # AS LINHAS DE VERDADE, agrupadas pela coordenada Y — a mesma escolha do
    # canastra, e pelo mesmo motivo escrito lá: é a forma que o nó
    # `Extract From File` do n8n entrega ao pipeline. `texto()` devolve uma
    # CÉLULA por pedaço, e contar célula como linha afrouxaria a régua.
    #
    # ESTE ARQUIVO USAVA `texto()` E O EXTRATOR CURTO. Medido em 01/09, antes da
    # troca: sobre a saída não agrupada a régua contava 3 onde a verdade é 99, e
    # 0 onde a verdade é 28 — erro médio de 93%, contando A MENOS em 13 de 13
    # documentos. Não era defeito da régua: era ela lendo célula em vez de linha,
    # exatamente o que o comentário do canastra avisa. O extrator curto (24
    # linhas, sem agrupamento por Y) saiu, e o do canastra entrou no lugar.
    _texto_por_arquivo[_arquivo] = [l for l in _extrai.linhas(_bruto) if l.strip()]
    _texto = "\n".join(_bruto_texto) if isinstance(_bruto_texto, list) else _bruto_texto
    _linhas = [linha for linha in _texto.split("\n") if linha.strip()]
    _metricas.append({
        "arquivo": _arquivo,
        "paginas": len(_re.findall(rb"/Type\s*/Page[^s]", _bruto)),
        "bytes": len(_bruto),
        "caracteres": len(_texto),
        "linhas_texto": len(_linhas),
        # Linha com dígito é candidata a virar linha financeira extraída — é ela
        # que vira token de SAÍDA, o item mais caro da conta.
        "linhas_com_numero": sum(1 for linha in _linhas if any(ch.isdigit() for ch in linha)),
        # A VERDADE DA COBERTURA, e ela NÃO é uma leitura do PDF: sai do
        # `R.CONTAGEM`, preenchido enquanto os flowables eram montados, ANTES de
        # o arquivo existir. É contra ela que a régua `linhasDeConta` é
        # calibrada, e ela só passou a existir aqui em 01/09 — até então o
        # `book-canastra` era o ÚNICO book com verdade de cobertura, e a
        # afirmação "régua exata em 20 de 20" descrevia 20 documentos de um
        # gerador só.
        **{k + "_verdade": _verdade[k] for k in ("linhas_de_conta", "contas_distintas")},
        "celulas_de_valor_verdade": _verdade["celulas_de_valor"],
    })

with open(f"{R.OUT}/TEXTO_EXTRAIDO.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-vertentes", "documentos": _texto_por_arquivo}, fh,
              indent=1, ensure_ascii=False)

with open(f"{R.OUT}/METRICAS.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-vertentes", "documentos": _metricas}, fh, indent=2, ensure_ascii=False)

print(f"METRICAS.json gravado: {len(_metricas)} documentos, "
      f"{sum(m['paginas'] for m in _metricas)} páginas, "
      f"{sum(m['linhas_com_numero'] for m in _metricas)} linhas com número")
