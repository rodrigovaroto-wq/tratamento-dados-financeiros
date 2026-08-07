# -*- coding: utf-8 -*-
"""Ponto de entrada do book CANASTRA: gera os PDFs, o gabarito e o guia.

    cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py

Saída em `pdf/` (não versionada — é determinística, basta rodar de novo).
"""

import json

import dados as D
import demonstracoes as X
import motor as M
import render as R

bp, tot = M.construir()

# Receita bruta das demais empresas (a da Indústria vive em demonstracoes.py).
RECEITA_OUTRAS = {
    "comercial": {2023: 96_000, 2024: 84_000, 2025: 71_000},
    "transportes": {2023: 34_000, 2024: 31_000, 2025: 26_000},
    "agro": {2023: 21_000, 2024: 19_500, 2025: 18_000},
    "imob": {2023: 4_600, 2024: 4_900, 2025: 5_200},
}

feitos = []


def gera(nome, fn, *a, **kw):
    feitos.append(fn(*a, **kw))
    return feitos[-1]


# ---------------------------------------------------------------------------
# OS DOCUMENTOS. A NUMERAÇÃO É A ORDEM EM QUE ELES CHEGAM NUM MANDATO REAL:
# primeiro as demonstrações da operacional, depois as das demais empresas, o
# combinado, e por fim os anexos que sustentam cada conta.
#
# Os NOMES DE ARQUIVO são metade do teste. Metade deles está na notação de
# f0/03 (`12M25`, `2025x2024`, `36 meses`), que o classificador resolve pelo
# nome — barato e determinístico. A outra metade está como o cliente manda de
# verdade: ano solto, sem período, ou "Doc1.pdf". Essa metade paga o PDF DUAS
# vezes à OpenAI (classificação por conteúdo + extração), e é ela que faz o
# lote estourar o teto de gasto. Ver `medir-custo-book.mjs`.
# ---------------------------------------------------------------------------
gera("bp industria", R.pdf_balanco, bp, tot, "industria", [2025, 2024, 2023],
     "01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf",
     nota_extra="Nota 2 — Em razão do descumprimento do índice de cobertura de juros contratado "
                "com o Banco Meridional S.A., parcela dos financiamentos originalmente "
                "classificada no passivo não circulante foi reclassificada para o circulante.")
gera("dre industria", R.pdf_dre, bp, tot, [2025, 2024, 2023],
     "02_DRE_Canastra_Industria_2025x2024x2023.pdf")
gera("dfc", R.pdf_dfc, bp, tot, 2025, "03_DFC_Canastra_Industria_12M25.pdf")
gera("dmpl", R.pdf_dmpl, bp, tot, "04_DMPL_Canastra_Industria_2023_a_2025.pdf")
gera("dva", R.pdf_dva, bp, tot, 2025, "05_DVA_Canastra_Industria_12M25.pdf")

gera("bp comercial", R.pdf_balanco, bp, tot, "comercial", [2025, 2024],
     "06_Balanco_Patrimonial_Canastra_Comercial_2025x2024.pdf",
     nota_extra="Nota 1 — A Sociedade apresenta PASSIVO A DESCOBERTO em 31/12/2025. A "
                "continuidade das operações depende de aporte da controladora e da renegociação "
                "dos débitos em atraso.")
gera("dre comercial", R.pdf_dre_condensada, bp, tot, "comercial", [2025, 2024],
     RECEITA_OUTRAS["comercial"], "07_DRE_Canastra_Comercial_2025x2024.pdf")
gera("bp holding", R.pdf_balanco, bp, tot, "holding", [2025, 2024],
     "08_Balanco_Patrimonial_Canastra_Participacoes_2025x2024.pdf",
     nota_extra="Nota 3 — Os investimentos em controladas são avaliados por equivalência "
                "patrimonial. Investimento em controlada com patrimônio líquido negativo é "
                "mantido por valor zero, registrando-se a parcela excedente como provisão para "
                "passivo a descoberto no passivo não circulante.")
gera("bp transportes", R.pdf_balanco, bp, tot, "transportes", [2025, 2024],
     "09_Balanco_Patrimonial_CN_Transportes_2025x2024.pdf")
gera("dre transportes", R.pdf_dre_condensada, bp, tot, "transportes", [2025, 2024],
     RECEITA_OUTRAS["transportes"], "10_DRE_CN_Transportes_2025x2024.pdf")
gera("bp agro", R.pdf_balanco, bp, tot, "agro", [2025, 2024],
     "11_Balanco_Patrimonial_Canastra_Agroflorestal_2025x2024.pdf")
gera("bp imob", R.pdf_balanco, bp, tot, "imob", [2025, 2024],
     "12_Balanco_Patrimonial_Canastra_Imobiliaria_SPE_2025x2024.pdf")

gera("combinado 2025", R.pdf_combinado, bp, tot, 2025,
     "13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf")
gera("combinado 2024", R.pdf_combinado, bp, tot, 2024,
     "14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf")

gera("balancete 2025", R.pdf_balancete, bp, 2025,
     "15_Balancete_Analitico_Canastra_Industria_12M25.pdf")
gera("balancete 2024", R.pdf_balancete, bp, 2024,
     "16_Balancete_Analitico_Canastra_Industria_12M24.pdf")
gera("razão", R.pdf_razao, bp, 2025,
     "17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf")

gera("faturamento", R.pdf_faturamento,
     "18_Faturamento_36_meses_Canastra_Industria_2023_a_2025.pdf")
gera("fat intragrupo", R.pdf_fat_intragrupo, bp,
     "19_Faturamento_Intragrupo_Grupo_Canastra_2023_a_2025.pdf")
gera("mapa dívida", R.pdf_mapa_divida, bp, 2025,
     "20_Mapa_de_Divida_Canastra_Industria_2025.pdf")
gera("mútuos", R.pdf_mutuos, bp, tot, 2025,
     "21_Mutuos_Intragrupo_Grupo_Canastra_2025.pdf")

ar_linhas, ar_total, ar_vencido = X.aging_recebiveis(bp, 2025)
gera("aging AR", R.pdf_aging, "AGING DE CONTAS A RECEBER POR CLIENTE",
     D.ENTIDADES["industria"], X.FAIXAS_AR, ar_linhas, ar_total, ar_vencido,
     "22_Aging_de_Contas_a_Receber_Canastra_Industria_2025.pdf", "Cliente / sacado",
     "(Valores expressos em milhares de reais — R$ mil)",
     nota="O total corresponde às duplicatas a receber BRUTAS (mercado interno e externo), antes "
          "das perdas estimadas e antes das operações de antecipação registradas como redutoras.")

ap_linhas, ap_total, ap_vencido = X.aging_pagaveis(bp, 2025)
gera("aging AP", R.pdf_aging, "AGING DE CONTAS A PAGAR POR FORNECEDOR",
     D.ENTIDADES["industria"], X.FAIXAS_AP, ap_linhas, ap_total, ap_vencido,
     "23_Aging_de_Contas_a_Pagar_Canastra_Industria_2025.pdf", "Fornecedor / credor",
     "Values in thousands of Brazilian Reais (BRL '000)", formato="us",
     nota="Report generated by ERP module AP-4400 (locale en-US). O total corresponde a "
          "fornecedores nacionais, estrangeiros e títulos vencidos, EXCLUÍDO o saldo intragrupo.")

gera("estoques", R.pdf_estoques, bp, 2025,
     "24_Posicao_de_Estoques_Canastra_Industria_2025.pdf")
gera("situação fiscal", R.pdf_situacao_fiscal, bp, 2025,
     "25_Situacao_Fiscal_e_Parcelamentos_Grupo_Canastra_2025.pdf")
gera("contingências", R.pdf_contingencias, bp, 2025,
     "26_Contingencias_e_Processos_Judiciais_Canastra_Industria_2025.pdf")
gera("imobilizado", R.pdf_imobilizado, bp, 2025,
     "27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf")
gera("folha", R.pdf_folha, 2025,
     "28_Folha_de_Pagamento_Canastra_Industria_2025.pdf")
gera("extratos", R.pdf_extratos, bp, 2025,
     "29_Extrato_Bancario_Consolidado_Canastra_Industria_2025.pdf")

gera("certidões", R.pdf_certidoes, "30_Certidoes_Negativas_Grupo_Canastra.pdf")
gera("contrato social", R.pdf_contrato_social, bp, tot,
     "31_Contrato_Social_Consolidado_Canastra_Industria.pdf")
gera("organograma", R.pdf_organograma, "32_Organograma_Societario_Grupo_Canastra.pdf")
gera("notas", R.pdf_notas, bp, tot, "33_Notas_Explicativas_Grupo_Canastra_12M25.pdf")
gera("parecer", R.pdf_parecer, "34_Relatorio_do_Auditor_Independente_2025.pdf")
gera("df completa", R.pdf_df_completa, bp, tot, 2024,
     "35_Demonstracoes_Contabeis_Canastra_Industria_2024x2023.pdf")

# --- os três que chegam com nome de vida real -------------------------------
gera("doc1", R.pdf_balanco, bp, tot, "agro", [2023], "Doc1.pdf")
gera("digitalizado", R.pdf_balancete, bp, 2025,
     "digitalizado_20260115_0003.pdf", "comercial")
gera("anexo iv", R.pdf_estoques, bp, 2024, "ANEXO IV - planilha final REV3.pdf")

print(f"{len(feitos)} PDFs gerados em {R.OUT}:")
for f in feitos:
    print("  ", f)


# ---------------------------------------------------------------- GABARITO ---
dre = X.dre_industria(bp, tot)
fat_linhas, fat_totais = X.faturamento_36m()
contratos, divida_total, juros_total = X.mapa_divida(bp, 2025)
mut_planilha, mut_total_planilha, mut_total_balanco = X.mutuos(bp, tot, 2025)
est_grupos, est_provisao, est_total = X.estoques(bp, 2025)
parcelamentos, correntes, provisoes_trib, tot_parc, tot_corr = X.situacao_fiscal(bp, 2025)
cont_linhas, cont_provisionado, cont_possivel, cont_remoto = X.contingencias(bp, 2025)
imo_linhas, imo_custo, imo_dep, imo_liquido = X.imobilizado(bp, 2025)
folha_linhas, headcount, folha_anual = X.folha(2025)
extrato_linhas, extrato_total = X.extratos(bp, 2025)
dfc_linhas, caixa_ini, caixa_fim = X.dfc(bp, tot, 2025)
dmpl_colunas, dmpl_mov = X.dmpl(bp, tot)
dva_geracao, dva_distribuicao, dva_total = X.dva(bp, tot, 2025)

gab = {
    "grupo": D.GRUPO,
    "exercicios": list(D.ANOS),
    "entidades": {k: D.ENTIDADES[k]["razao_social"] for k in D.ENTIDADES},
    "cnpj": {k: D.ENTIDADES[k]["cnpj"] for k in D.ENTIDADES},
    "participacao": D.PARTICIPACAO,
    "balanco_por_entidade": {
        str(ano): {k: {ch: tot[ano][k][ch] for ch in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL")}
                   for k in D.ORDEM}
        for ano in D.ANOS},
    "combinado": {
        str(ano): {kk: vv for kk, vv in M.combinado(bp, tot, ano).items()
                   if kk in ("ativo", "passivo", "pl", "nci", "elim_invest",
                             "elim_mutuos", "elim_provisao", "pl_holding")}
        for ano in D.ANOS},
    "dre_industria": {str(ano): X.ancoras(dre[ano]) for ano in D.ANOS},
    "receita_bruta_industria": {str(a): v for a, v in X.RECEITA_BRUTA.items()},
    "resultado_industria": {str(a): v for a, v in X.resultado_alvo(tot).items()},
    "faturamento_total_R$": {str(a): v for a, v in fat_totais.items()},
    "faturamento_meses": len(fat_linhas),
    "divida_bancaria_R$": divida_total,
    "divida_bancaria_R$mil": X.divida_bancaria(bp, 2025),
    "juros_exercicio_R$": juros_total,
    "despesa_financeira_DRE_R$mil": abs(
        [v for r, v, t in dre[2025] if r.startswith("(-) Despesas financeiras")][0]),
    "contratos_de_divida": len(contratos),
    "tranche_em_dolar_USD": [c["saldo_usd"] for c in contratos if c["saldo_usd"]][0],
    "cambio_fechamento_2025": X.CAMBIO_FECHAMENTO[2025],
    "mutuos_planilha": mut_total_planilha,
    "mutuos_balanco": mut_total_balanco,
    "divergencia_mutuos": mut_total_balanco - mut_total_planilha,
    "aging_recebiveis_total": ar_total,
    "aging_recebiveis_vencido": ar_vencido,
    "aging_pagaveis_total": ap_total,
    "aging_pagaveis_vencido": ap_vencido,
    "estoques_total": est_total,
    "estoques_provisao": est_provisao,
    "parcelamentos_total": tot_parc,
    "tributos_correntes_total": tot_corr,
    "contingencias_provisionado": cont_provisionado,
    "contingencias_possivel": cont_possivel,
    "contingencias_remoto": cont_remoto,
    "imobilizado_custo": imo_custo,
    "imobilizado_depreciacao": imo_dep,
    "imobilizado_liquido": imo_liquido,
    "headcount": headcount,
    "folha_custo_anual": folha_anual,
    "disponivel_2025": extrato_total,
    "dfc_caixa_inicial": caixa_ini,
    "dfc_caixa_final": caixa_fim,
    "dmpl_saldo_final": dmpl_mov[-1][1],
    "dva_total_distribuir": dva_total,
    "documentos": feitos,
}
with open(f"{R.OUT}/GABARITO.json", "w", encoding="utf-8") as fh:
    json.dump(gab, fh, indent=2, ensure_ascii=False)


# ------------------------------------------------------------ GUIA DE TESTE --
def f(v):
    return f"{v:,}".replace(",", ".")


def dec(v, n=2):
    return f"{v:.{n}f}".replace(".", ",")


def linha_pl(k):
    return " → ".join(f(tot[a][k]["PL"]) for a in D.ANOS)


t = {a: tot[a]["industria"] for a in D.ANOS}
lc = {a: t[a]["AC"] / t[a]["PC"] for a in D.ANOS}
mb = {a: X.ancoras(dre[a])["LUCRO BRUTO"] / X.ancoras(dre[a])["RECEITA OPERACIONAL LÍQUIDA"] * 100
      for a in D.ANOS}

guia = f"""# Book de teste — GRUPO CANASTRA (dados sintéticos, três exercícios)

Grupo industrial fictício **em deterioração progressiva**, com 6 empresas sob controle comum e
**{len(feitos)} documentos** cobrindo os exercícios de **2023, 2024 e 2025**. Todos os documentos são
sintéticos e trazem essa marcação no rodapé. Nenhum corresponde a empresa, pessoa ou fato real.

Regenerar: `PYTHONPATH=. python3 gerar.py` (requer `reportlab`). Os números são calculados e
**validados por assert** — nenhum total é digitado à mão, o balanço fecha nas seis empresas e nos
três exercícios, e cada anexo soma exatamente a conta do balanço que ele detalha.

## Por que ele existe, se já há o `book-vertentes`

O primeiro book é fácil em três dimensões que a produção não é, e as três estão cobertas aqui:

| | `book-vertentes` | `book-canastra` |
|---|---|---|
| Exercícios | 2 | **3** (2023, 2024, 2025) |
| Empresas | 5 | **6** (uma delas fornecedora das outras) |
| Documentos | 14 | **{len(feitos)}** |
| Tipos documentais | 8 | **16** (aging, estoque, fiscal, contingência, folha, imobilizado, razão, certidão, organograma, parecer…) |
| Contas que nascem/morrem no meio do histórico | não | **sim** (antecipação de recebíveis, parcelamento, direito de uso, reserva) |
| Nomes de arquivo | todos na notação de f0/03 | **metade como o cliente manda de verdade** |
| Lote cabe no teto de gasto | sim | **não — e é isso que ele mede** |

## A história (o que esperar da análise)

Fabricante de embalagens de papelão ondulado que perdeu a cliente âncora em 2024 e viu o custo do
papel kraft subir sem repasse ao preço. Em 2025 opera com capital de terceiros, quebra o covenant de
cobertura de juros (a dívida de longo prazo desce inteira para o circulante), adere à transação
tributária federal e antecipa recebíveis para fechar o mês. Uma controlada já está com **passivo a
descoberto**; os imóveis da SPE e a floresta plantada da agroflorestal são o que ainda sustenta o
patrimônio combinado.

| Entidade | Papel | PL 2023 → 2024 → 2025 (R$ mil) |
|---|---|---|
| {D.ENTIDADES['holding']['razao_social']} | Holding (MEP) | {linha_pl('holding')} |
| {D.ENTIDADES['industria']['razao_social']} | Operacional principal | {linha_pl('industria')} |
| {D.ENTIDADES['comercial']['razao_social']} | Distribuição | {linha_pl('comercial')} |
| {D.ENTIDADES['transportes']['razao_social']} | Logística (65%) | {linha_pl('transportes')} |
| {D.ENTIDADES['agro']['razao_social']} | Matéria-prima (verticalização) | {linha_pl('agro')} |
| {D.ENTIDADES['imob']['razao_social']} | Imóveis do grupo | {linha_pl('imob')} |

**A trajetória da Indústria, que é o que o modelo tem de reproduzir:** liquidez corrente
{dec(lc[2023])} → {dec(lc[2024])} → **{dec(lc[2025])}**; capital circulante líquido
{f(t[2023]['AC'] - t[2023]['PC'])} → {f(t[2024]['AC'] - t[2024]['PC'])} →
**{f(t[2025]['AC'] - t[2025]['PC'])}**; margem bruta {dec(mb[2023], 1)}% → {dec(mb[2024], 1)}% →
**{dec(mb[2025], 1)}%**; resultado {f(X.LUCRO_2023)} → {f(X.resultado_alvo(tot)[2024])} →
**{f(X.resultado_alvo(tot)[2025])}**.

## Os {len(feitos)} documentos e o que cada um estressa

| # | Documento | O que testa no pipeline |
|---|---|---|
| 01 | BP Indústria 2025×2024×2023 | **Três colunas de exercício**; contas que não existem em todos os anos (célula vazia, não zero) |
| 02 | DRE Indústria 3 exercícios | Cascata completa; linha (impairment) que só existe em 2024 |
| 03 | DFC 2025 (indireto) | Amarra com o Disponível do balanço |
| 04 | DMPL 2023–2025 | **Três** linhas "SALDOS EM 31 DE DEZEMBRO DE…" e uma transferência entre contas do PL |
| 05 | DVA 2025 | Demonstração cuja soma fecha por construção — geração × distribuição |
| 06–07 | BP e DRE Comercial | **Passivo a descoberto**: indicadores negativos sem quebrar |
| 08 | BP Holding | **MEP** e provisão para passivo a descoberto — vocabulário raro |
| 09–12 | BP/DRE das demais | Planos de contas enxutos; **ativos biológicos** e **propriedades para investimento** |
| 13–14 | **BP COMBINADO 2025 e 2024** | Uma coluna por empresa + **Eliminações** (que não é empresa) + não controladores |
| 15–16 | Balancetes analíticos | Colunas **D/C**: a natureza determina o sinal, e conta redutora inverte |
| 17 | Livro Razão (Fornecedores) | ~100 lançamentos, débito/crédito, saldo corrente — **volume de linhas** |
| 18 | Faturamento 36 meses | Série mensal **cronológica**; escala em REAIS; colunas não monetárias |
| 19 | Faturamento intragrupo | Os saldos que o combinado elimina, pelos dois lados |
| 20 | **Mapa de dívida** | **REAIS** (×1.000 do balanço) e **tranche em DÓLAR** com duas colunas de saldo |
| 21 | Mútuos intragrupo | **Divergência deliberada de R$ {f(gab['divergencia_mutuos'])} mil** contra o balanço |
| 22 | Aging de recebíveis | Faixas de vencimento + coluna de **percentual** |
| 23 | Aging de pagáveis | **Separador decimal anglo** (`1,234.56`) no meio de um kit em português |
| 24 | Posição de estoques | **Quantidade física** (t, milheiro, unidade) e custo unitário ao lado do valor |
| 25 | Situação fiscal | **Parcelamento × tributo corrente × provisão** — as três naturezas que o modelo projeta diferente |
| 26 | Contingências | **Provável × possível × remoto**: só o provável está no passivo |
| 27 | Composição do imobilizado | **Taxa de depreciação por classe** (a vida útil que o Kit Básico não coleta) |
| 28 | Folha de pagamento | **Efetivo em pessoas** ao lado de custo em R$ mil |
| 29 | Extrato bancário consolidado | Amarra com o Disponível; PDF com **marca d'água** por cima |
| 30 | Certidões | **Nenhum valor monetário** — não deve gerar linha financeira |
| 31 | Contrato social | Texto jurídico; o capital social citado é o do balanço |
| 32 | Organograma societário | Só percentuais de participação |
| 33 | Notas explicativas | Texto corrido (going concern, covenant, transação tributária) |
| 34 | Parecer do auditor | **Opinião com ressalva** — texto, sem tabela |
| 35 | Demonstrações Contábeis 2024×2023 | **PDF COMPOSTO**: balanço + DRE + DFC + notas num arquivo só |
| — | `Doc1.pdf` | Nome que não diz nada → classificação por **conteúdo** |
| — | `digitalizado_20260115_0003.pdf` | Nome de scanner → classificação por conteúdo |
| — | `ANEXO IV - planilha final REV3.pdf` | Nome de anexo de e-mail → classificação por conteúdo |

## Gabarito (confira contra o export)

**Balanço — Canastra Indústria (R$ mil)**

| | 2025 | 2024 | 2023 |
|---|---|---|---|
| Ativo Circulante | {f(t[2025]['AC'])} | {f(t[2024]['AC'])} | {f(t[2023]['AC'])} |
| Ativo Não Circulante | {f(t[2025]['ANC'])} | {f(t[2024]['ANC'])} | {f(t[2023]['ANC'])} |
| **TOTAL DO ATIVO** | **{f(t[2025]['ATIVO'])}** | **{f(t[2024]['ATIVO'])}** | **{f(t[2023]['ATIVO'])}** |
| Passivo Circulante | {f(t[2025]['PC'])} | {f(t[2024]['PC'])} | {f(t[2023]['PC'])} |
| Passivo Não Circulante | {f(t[2025]['PNC'])} | {f(t[2024]['PNC'])} | {f(t[2023]['PNC'])} |
| Patrimônio Líquido | {f(t[2025]['PL'])} | {f(t[2024]['PL'])} | {f(t[2023]['PL'])} |

**Combinado 2025:** Ativo **{f(gab['combinado']['2025']['ativo'])}** = Passivo
{f(gab['combinado']['2025']['passivo'])} + PL {f(gab['combinado']['2025']['pl'])}
(controladores {f(gab['combinado']['2025']['pl_holding'])} + não controladores
{f(gab['combinado']['2025']['nci'])}). Eliminações: investimentos
{f(gab['combinado']['2025']['elim_invest'])}, passivo a descoberto
{f(gab['combinado']['2025']['elim_provisao'])}, intragrupo {f(gab['combinado']['2025']['elim_mutuos'])}.

**DRE Indústria 2025:** Receita bruta {f(X.RECEITA_BRUTA[2025])} · Receita líquida
{f(X.ancoras(dre[2025])['RECEITA OPERACIONAL LÍQUIDA'])} · Lucro bruto
{f(X.ancoras(dre[2025])['LUCRO BRUTO'])} · EBIT
{f(X.ancoras(dre[2025])['RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO'])} ·
**Prejuízo {f(X.resultado_alvo(tot)[2025])}**

**Amarrações que a reconciliação tem de encontrar:**

- Ativo = Passivo + PL nas **seis** entidades, nos **três** exercícios, e no combinado dos três.
- Resultado da DRE de cada ano = variação do PL do próprio balanço (2024: {f(X.resultado_alvo(tot)[2024])};
  2025: {f(X.resultado_alvo(tot)[2025])}) e = movimentação da DMPL.
- Saldo final de caixa da DFC (**{f(caixa_fim)}**) = Disponível do balanço 2025 = total do extrato
  bancário consolidado.
- Soma do faturamento mensal de 2025 (**R$ {f(fat_totais[2025])}**, em reais) = Receita Operacional
  Bruta da DRE (**{f(X.RECEITA_BRUTA[2025])}** em R$ mil) — **escalas diferentes de propósito**.
- Soma dos saldos do mapa de dívida (**R$ {f(divida_total)}**) = dívida bancária do balanço
  (**{f(gab['divida_bancaria_R$mil'])}** em R$ mil); soma dos juros (**R$ {f(juros_total)}**) =
  despesas financeiras da DRE (**{f(gab['despesa_financeira_DRE_R$mil'])}** em R$ mil).
- Aging de recebíveis (**{f(ar_total)}**) = duplicatas a receber brutas; aging de pagáveis
  (**{f(ap_total)}**) = fornecedores, sem o intragrupo.
- Estoques por item (**{f(est_total)}**) = subgrupo Estoques do balanço, provisão inclusa.
- Parcelamentos da situação fiscal (**{f(tot_parc)}**) = contas de parcelamento do balanço;
  contingências provisionadas (**{f(cont_provisionado)}**) = provisões do não circulante.
- Imobilizado: custo {f(imo_custo)} − depreciação {f(imo_dep)} = líquido **{f(imo_liquido)}**.

## Armadilhas deliberadas (é aqui que o sistema deve se provar)

1. **Três exercícios, e contas que não existem em todos.** Antecipação de recebíveis e direito de
   uso nascem em 2024; parcelamento tributário, crédito presumido e tributo diferido nascem em 2025;
   importações em andamento e a reserva de lucros a realizar somem. Célula vazia **não é zero**.
2. **O mesmo saldo com dois nomes.** "Duplicatas a receber de clientes - mercado interno" (2023/2024)
   vira "Clientes - duplicatas a receber - mercado interno" (2025). É a mesma conta.
3. **Quatro escalas no mesmo caso** — demonstrações em R$ mil, mapa de dívida e faturamento em
   reais, estoques em quantidade física, folha em pessoas.
4. **Separador decimal anglo** no aging de pagáveis (`1,234.56`), como um ERP em locale `en-US`
   exporta. Trocar ponto por vírgula sem olhar erra por 1.000×.
5. **Tranche em DÓLAR** no mapa de dívida, com saldo em US$ e o equivalente em R$ lado a lado.
   Somar a coluna errada erra por ~{dec(X.CAMBIO_FECHAMENTO[2025], 1)}×.
6. **Coluna "Eliminações" no combinado** — não é uma empresa. E há **não controladores** (35% da CN
   Transportes), então "combinado = soma das colunas" está errado por construção.
7. **Nomenclatura diferente para a mesma conta entre empresas** — "Disponibilidades" (Indústria),
   "Numerário Disponível" (Comercial), "Bancos Conta Movimento" (CN Transportes), "Caixa e Bancos"
   (Agroflorestal), "Caixa" (SPE), "Caixa e Equivalentes de Caixa" (holding).
8. **Linhas de DMPL** ("SALDOS EM 31 DE DEZEMBRO DE 2024") são posição, não movimentação — e agora
   são três.
9. **Contingências por prognóstico**: somar provável + possível + remoto infla o passivo em
   {f(cont_possivel + cont_remoto)} contra os {f(cont_provisionado)} realmente provisionados.
10. **Contas redutoras entre parênteses** (PECLD, depreciação, obsolescência, antecipação) precisam
    virar negativo; no balancete, quem dá o sinal é a coluna **D/C**.
11. **Divergência de R$ {f(gab['divergencia_mutuos'])} mil** entre a planilha de mútuos e o balanço —
    é a única do book, e deve aparecer para o humano.
12. **Documentos sem valor monetário** (certidões, organograma, parecer, contrato social) não podem
    gerar linha financeira.
13. **PDF composto** (documento 35): quatro demonstrações num arquivo só.
14. **Três arquivos com nome de vida real** (`Doc1.pdf`, `digitalizado_...`, `ANEXO IV - ...`), que
    forçam classificação por conteúdo — e **pagam o PDF duas vezes**.
15. **O lote não cabe no teto de gasto.** Com {len(feitos)} documentos, a decisão de orçamento tem de
    ser NÃO antes da primeira chamada. Rodar `node n8n/medir-custo-book.mjs` para o veredito medido.
"""
with open(f"{R.OUT}/GUIA_DE_TESTE.md", "w", encoding="utf-8") as fh:
    fh.write(guia)

print("\nGABARITO.json e GUIA_DE_TESTE.md gravados em", R.OUT)


# ------------------------------------------------------------------ MÉTRICAS -
# O que a extração vai PAGAR por documento, medido no artefato (não estimado):
# páginas, caracteres de texto e linhas com número. É o insumo de
# `n8n/medir-custo-book.mjs`, que converte isso em dólares com o preço e as
# funções de orçamento que rodam em produção.
import re

import extrai

metricas = []
for arquivo in feitos:
    caminho = f"{R.OUT}/{arquivo}"
    bruto = open(caminho, "rb").read()
    texto = extrai.texto(caminho)
    linhas_texto = [linha for linha in texto.split("\n") if linha.strip()]
    metricas.append({
        "arquivo": arquivo,
        "paginas": len(re.findall(rb"/Type\s*/Page[^s]", bruto)),
        "bytes": len(bruto),
        "caracteres": len(texto),
        "linhas_texto": len(linhas_texto),
        # Linha com dígito é candidata a virar linha financeira extraída — é ela
        # que vira token de SAÍDA, que é o item mais caro da conta.
        "linhas_com_numero": sum(1 for linha in linhas_texto if any(ch.isdigit() for ch in linha)),
    })

with open(f"{R.OUT}/METRICAS.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-canastra", "documentos": metricas}, fh, indent=2, ensure_ascii=False)

print(f"METRICAS.json gravado: {len(metricas)} documentos, "
      f"{sum(m['paginas'] for m in metricas)} páginas, "
      f"{sum(m['linhas_com_numero'] for m in metricas)} linhas com número")
