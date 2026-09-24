# -*- coding: utf-8 -*-
"""Ponto de entrada do book PIRAQUARA (distress): PDFs, gabarito e métricas.

    cd "Dados de Teste"/book-distress && PYTHONPATH=. python3 gerar.py

Saída em `pdf/` (não versionada — é determinística ao BYTE, basta rodar de novo;
ver `render.py` sobre `rl_config.invariant`).
"""

import json
import re

import dados as D
import demonstracoes as X
import extrai
import motor as M
import render as R

bp, tot, dre = M.construir()
ANOS3 = [2025, 2024, 2023]
feitos = []


def gera(fn, *a, **kw):
    feitos.append(fn(*a, **kw))
    return feitos[-1]


def f(v):
    return R.num(v)


t25 = tot[2025]["metalurgica"]
cov = X.covenant(bp, dre["metalurgica"])

# ---------------------------------------------------------------------------
# OS DOCUMENTOS, na ordem em que chegam num mandato de reestruturação: as
# demonstrações da operacional em distress, as das outras duas, e os anexos que
# sustentam a tese (dívida + covenant, mútuos, aging, extrato), por fim o texto.
# Todos os nomes seguem a notação de `2 Especificação/f0/03` — este book testa
# CONTEÚDO de distress, não classificação por nome (isso é o canastra).
# ---------------------------------------------------------------------------
gera(R.pdf_balanco, bp, tot, "metalurgica", ANOS3,
     "01_Balanco_Patrimonial_Piraquara_Metalurgica_2025x2024x2023.pdf",
     nota_extra=[
         f"Nota 2 — A Sociedade apresenta PASSIVO A DESCOBERTO de R$ {f(abs(t25['PL']))} mil em "
         "31/12/2025. Ver Nota 1 sobre a continuidade operacional.",
         "Nota 3 — Em razão do descumprimento do índice Dívida Líquida/EBITDA, os empréstimos de "
         "longo prazo foram reclassificados para o passivo circulante em 31/12/2025.",
     ])
gera(R.pdf_dre, R.unifica_resultado(dre["metalurgica"]), "metalurgica", ANOS3,
     "02_DRE_Piraquara_Metalurgica_2025x2024x2023.pdf",
     notas=["Nota — As despesas financeiras estão apresentadas BRUTAS, separadas das receitas "
            "financeiras. Não foi reconhecido imposto de renda diferido ativo sobre o prejuízo "
            "fiscal de 2025 (Nota 6)."])
gera(R.pdf_dfc, bp, dre["metalurgica"], [2025, 2024],
     "03_DFC_Piraquara_Metalurgica_2025x2024.pdf")
gera(R.pdf_balanco, bp, tot, "servicos", ANOS3,
     "04_Balanco_Patrimonial_Piraquara_Montagens_2025x2024x2023.pdf")
gera(R.pdf_dre, R.unifica_resultado(dre["servicos"]), "servicos", ANOS3,
     "05_DRE_Piraquara_Montagens_2025x2024x2023.pdf")
gera(R.pdf_balanco, bp, tot, "holding", ANOS3,
     "06_Balanco_Patrimonial_Piraquara_Participacoes_2025x2024x2023.pdf",
     nota_extra=["Nota 4 — Investimentos avaliados por equivalência patrimonial. O investimento na "
                 "Piraquara Metalúrgica, cujo patrimônio líquido é negativo em 31/12/2025, é mantido "
                 "por valor zero, e a parcela excedente está registrada como provisão para passivo "
                 "a descoberto no passivo não circulante."])
gera(R.pdf_dre, R.unifica_resultado(dre["holding"]), "holding", ANOS3,
     "07_DRE_Piraquara_Participacoes_2025x2024x2023.pdf",
     notas=["Nota — A equivalência patrimonial da Piraquara Metalúrgica reconhece o prejuízo "
            "integral do exercício: a parcela que excede o investimento é levada à provisão para "
            "passivo a descoberto."])
gera(R.pdf_mapa_divida, bp, dre["metalurgica"], 2025,
     "08_Mapa_de_Divida_e_Covenant_Piraquara_Metalurgica_2025.pdf")
gera(R.pdf_mutuos, bp, 2025, "09_Mutuos_Intragrupo_Grupo_Piraquara_2025.pdf")

ap_linhas, ap_faixas, ap_total = X.aging_ap(bp, 2025)
gera(R.pdf_aging, "AGING DE CONTAS A PAGAR POR FORNECEDOR", ap_linhas, ap_faixas, ap_total,
     "10_Aging_de_Contas_a_Pagar_Piraquara_Metalurgica_2025.pdf", "Fornecedor",
     notas=["O total corresponde ao subgrupo Fornecedores do balanço (nacionais e estrangeiros). "
            "O saldo em moeda estrangeira está convertido pela taxa de fechamento."])
ar_linhas, ar_faixas, ar_total = X.aging_ar(bp, 2025)
gera(R.pdf_aging, "AGING DE CONTAS A RECEBER POR CLIENTE", ar_linhas, ar_faixas, ar_total,
     "11_Aging_de_Contas_a_Receber_Piraquara_Metalurgica_2025.pdf", "Cliente",
     notas=["O total corresponde às duplicatas a receber BRUTAS, antes das perdas estimadas em "
            f"créditos de liquidação duvidosa (R$ {f(-X.valor(bp[2025]['metalurgica'], 'AC', 'Contas a Receber', '(-) Perdas'))} mil)."])
gera(R.pdf_extrato, bp, 2025,
     "12_Extrato_Bancario_Banco_Tapajos_cc_20417-3_Piraquara_Metalurgica_2025.pdf")
gera(R.pdf_notas, bp, tot, dre, "13_Notas_Explicativas_Piraquara_Metalurgica_12M25.pdf")

# O parecer é texto: a verdade dele é ZERO linha financeira por declaração, como
# no canastra (armadilha 12 do GUIA_DE_TESTE de lá).
R.SEM_VALOR_MONETARIO.add("14_Relatorio_do_Auditor_Independente_Piraquara_Metalurgica_2025.pdf")
gera(R.pdf_parecer, bp, tot, "14_Relatorio_do_Auditor_Independente_Piraquara_Metalurgica_2025.pdf")

print(f"{len(feitos)} PDFs gerados em {R.OUT}")


# ---------------------------------------------------------------- GABARITO ---
def ancora(ent, ano, rot):
    return X.ancoras(dre[ent][ano])[rot]


def linha(ent, ano, prefixo):
    return next(v for r, v, _t in dre[ent][ano] if r.startswith(prefixo))


dfc = {a: X.dfc_metalurgica(bp, dre["metalurgica"], a)[1] for a in (2024, 2025)}
meses, ext_ini, ext_fim = X.extrato(bp, 2025)
tm = X.mutuos_tabela()
var = X.variacoes_met(bp)

gab = {
    "grupo": D.GRUPO,
    "exercicios": list(D.ANOS),
    "escala": "R$ mil, exceto o extrato bancário (R$ com centavos)",
    "entidades": {k: D.ENTIDADES[k]["razao_social"] for k in D.ORDEM},
    "cnpj": {k: D.ENTIDADES[k]["cnpj"] for k in D.ORDEM},
    "balanco_por_entidade": {
        str(a): {k: {ch: tot[a][k][ch] for ch in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL", "caixa")}
                 for k in D.ORDEM} for a in D.ANOS},
    "pl_negativo": {"entidade": "metalurgica", "exercicio": 2025, "pl": t25["PL"],
                    "provisao_passivo_a_descoberto_na_holding":
                        X.valor(bp[2025]["holding"], "PNC", "Provisões", "Provisão para passivo")},
    "resultado": {k: {str(a): X.resultado(dre[k][a]) for a in D.ANOS} for k in D.ORDEM},
    "dre_metalurgica": {str(a): {
        "receita_bruta": ancora("metalurgica", a, "RECEITA OPERACIONAL BRUTA"),
        "receita_liquida": ancora("metalurgica", a, "RECEITA OPERACIONAL LÍQUIDA"),
        "lucro_bruto": ancora("metalurgica", a, "LUCRO BRUTO"),
        "ebit": ancora("metalurgica", a, "RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"),
        "receitas_financeiras": ancora("metalurgica", a, "RECEITAS FINANCEIRAS"),
        "despesas_financeiras_brutas": ancora("metalurgica", a, "(-) DESPESAS FINANCEIRAS"),
        "juros_bancarios": linha("metalurgica", a, "(-) Juros sobre empréstimos"),
        "juros_mutuos": linha("metalurgica", a, "(-) Juros sobre mútuos"),
        "resultado_financeiro_liquido": ancora("metalurgica", a, "RESULTADO FINANCEIRO LÍQUIDO"),
        "depreciacao": var[a]["depreciacao"],
        "impairment": var[a]["impairment"],
        "resultado": X.resultado(dre["metalurgica"][a]),
    } for a in D.ANOS},
    "covenant": {"formula": "Dívida bancária − Disponível ≤ 3,0 × (EBIT + depreciação + impairment)",
                 "limite": D.COVENANT_LIMITE,
                 **{str(a): cov[a] for a in D.ANOS}},
    "divida_bancaria": {str(a): X.divida_bancaria(a) for a in D.ANOS},
    "emprestimos_classificacao": {str(a): dict(zip(("circulante", "reclassificado_covenant",
                                                    "nao_circulante"), X.saldos_emprestimos(a)))
                                  for a in D.ANOS},
    "contratos_de_divida_2025": len(X.mapa_divida(2025)),
    "mutuos": {m["contrato"]: {"mutuante": m["mutuante"], "mutuaria": m["mutuaria"],
                               **{str(a): tm[m["contrato"]][a] for a in D.ANOS}} for m in D.MUTUOS},
    "aging_ap": {"total": ap_total, "por_faixa": dict(zip(X.FAIXAS, ap_faixas)),
                 "acima_90": ap_faixas[-1], "linhas": len(ap_linhas),
                 "fornecedores_bp": X.soma(bp[2025]["metalurgica"]["PC"]["Fornecedores"])},
    "aging_ar": {"total": ar_total, "por_faixa": dict(zip(X.FAIXAS, ar_faixas)),
                 "acima_90": ar_faixas[-1], "linhas": len(ar_linhas),
                 "pecld_bp": -X.valor(bp[2025]["metalurgica"], "AC", "Contas a Receber", "(-) Perdas")},
    "extrato_bancario": {"conta": "Banco Tapajós S.A. ag. 0418 c/c 20.417-3", "meses": len(meses),
                         "saldo_inicial_R$": ext_ini / 100, "saldo_final_R$": ext_fim / 100,
                         "saldo_final_R$mil_arredondado": round(ext_fim / 100_000),
                         "caixa_bp_2025": t25["caixa"]},
    "dfc_metalurgica": {str(a): dfc[a] for a in dfc},
    "documentos": feitos,
}
with open(f"{R.OUT}/GABARITO.json", "w", encoding="utf-8") as fh:
    json.dump(gab, fh, indent=2, ensure_ascii=False)


# ------------------------------------------------------------------ MÉTRICAS -
# Mesmo formato do book-canastra: o que a extração vai pagar por documento,
# medido no artefato, e a VERDADE (linhas de conta) contada pelo gerador.
metricas, texto_por_arquivo = [], {}
for arquivo in feitos:
    bruto = open(f"{R.OUT}/{arquivo}", "rb").read()
    texto = extrai.texto(bruto)
    linhas_texto = [ln for ln in texto.split("\n") if ln.strip()]
    texto_por_arquivo[arquivo] = [ln for ln in extrai.linhas(bruto) if ln.strip()]
    verdade = R.CONTAGEM.get(arquivo, {"linhas_de_conta": 0, "celulas_de_valor": 0,
                                       "contas_distintas": 0})
    metricas.append({
        "arquivo": arquivo,
        "paginas": len(re.findall(rb"/Type\s*/Page[^s]", bruto)),
        "bytes": len(bruto),
        "caracteres": len(texto),
        "linhas_texto": len(linhas_texto),
        "linhas_com_numero": sum(1 for ln in linhas_texto if any(ch.isdigit() for ch in ln)),
        "linhas_de_conta_verdade": verdade["linhas_de_conta"],
        "celulas_de_valor_verdade": verdade["celulas_de_valor"],
        "contas_distintas_verdade": verdade["contas_distintas"],
    })

with open(f"{R.OUT}/METRICAS.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-distress", "documentos": metricas}, fh, indent=2, ensure_ascii=False)
with open(f"{R.OUT}/TEXTO_EXTRAIDO.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-distress", "documentos": texto_por_arquivo}, fh,
              indent=1, ensure_ascii=False)

print(f"GABARITO.json, METRICAS.json e TEXTO_EXTRAIDO.json gravados: {len(metricas)} documentos, "
      f"{sum(m['paginas'] for m in metricas)} páginas, "
      f"{sum(m['linhas_de_conta_verdade'] for m in metricas)} linhas de conta (verdade)")
