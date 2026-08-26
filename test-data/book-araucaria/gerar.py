# -*- coding: utf-8 -*-
"""Gera o book ARAUCÁRIA — 190 documentos e 5 exercícios (2021 a 2025).

    PYTHONPATH=. python3 gerar.py

Escreve `./pdf/` com os 190 PDFs, o `GABARITO.json`, o `METRICAS.json` e o
`GUIA_DE_TESTE.md`.

COMO ESTE ARQUIVO É ORGANIZADO, e por que não é uma lista de 190 chamadas
escritas à mão. Com 38 documentos a lista explícita ainda cabe na cabeça de quem
lê; com 190 ela vira o lugar onde um documento entra duas vezes, ou onde um ano
fica de fora, sem que nada acuse. Aqui os documentos são gerados por FAMÍLIA, em
laços sobre as empresas e os exercícios que de fato existem, e o total é
CONFERIDO no fim — junto com a unicidade dos nomes de arquivo.

O nome do arquivo sai de `nome()` ou de `NOMES_DE_CLIENTE`: metade do kit chega
na notação organizada e metade chega como o cliente manda. Ver a armadilha
`nome_de_arquivo_mudo` em `bagunca.py`.
"""

import json
import unicodedata
from datetime import date

import dados as D
import motor as M
import demonstracoes as X
import render as R
import bagunca as B

bp, tot = M.construir()
import os
import glob

# A SAÍDA É APAGADA ANTES DE SER ESCRITA.
#
# Não é higiene: o número de documentos e os nomes deles dependem do número de
# exercícios e de empresas. Quando o histórico passou de quatro para cinco anos,
# o `pdf/` ficou com os 190 novos E os 190 antigos, com nomes parecidos e
# períodos diferentes — 380 arquivos, e o kit inteiro contando duas histórias.
# Um book velho misturado com o novo é pior que book nenhum, porque parece
# certo. O `assert` de 190 documentos não pegava isso: ele conta o que foi
# GERADO, não o que está no diretório.
os.makedirs(R.OUT, exist_ok=True)
for velho_arq in glob.glob(os.path.join(R.OUT, "*")):
    os.remove(velho_arq)

feitos = []


def gera(rotulo, fn, *a, **kw):
    arq = fn(*a, **kw)
    feitos.append(arq)
    return arq


def slug(txt):
    s = unicodedata.normalize("NFKD", txt).encode("ascii", "ignore").decode()
    for ch in " /,()—-":
        s = s.replace(ch, "_")
    while "__" in s:
        s = s.replace("__", "_")
    return s.strip("_")


N = [0]


def nome(titulo, ent=None, anos=None, sufixo=None):
    """O nome ORGANIZADO: número sequencial, título, empresa e período."""
    N[0] += 1
    partes = [f"{N[0]:03d}", slug(titulo)]
    if ent:
        partes.append(slug(D.ENTIDADES[ent]["nome_fantasia"]))
    if anos:
        partes.append("x".join(str(a) for a in anos))
    if sufixo:
        partes.append(slug(sufixo))
    return "_".join(partes) + ".pdf"


def anos_de(ent, ordem_decrescente=True):
    a = [x for x in D.ANOS if D.existe_em(ent, x)]
    return list(reversed(a)) if ordem_decrescente else a


def ultimo_ano(ent):
    return anos_de(ent)[0]


# Receita bruta das demais empresas: proporcional ao ativo, com giro por perfil.
# Não é arbitrária — é o que sustenta a DRE condensada de cada uma fechar contra
# a variação do PL do balanço, que é a amarração que o `assert` cobra.
GIRO = {"paineis": 1.15, "moveis": 1.55, "comercial": 2.40, "florestal": .32,
        "transportes": 1.30, "varejo": 1.85, "imob": .14, "agro": .42,
        "servicos": 1.05, "metais": 1.40, "energia": .28, "trading": 2.90}
RECEITA_OUTRAS = {
    ent: {a: int(round(tot[a][ent]["ATIVO"] * g / 100) * 100) for a in anos_de(ent)}
    for ent, g in GIRO.items()
}


# ===========================================================================
# A. BALANÇOS PATRIMONIAIS — 34
# ===========================================================================
NOTA_INCORP = ("Em 30 de junho de 2024 a Companhia incorporou o acervo líquido da Araucária "
               "Ferragens e Metais Ltda. (CNPJ 27.884.126/0001-69), conforme protocolo de "
               "incorporação de 12 de maio de 2024. Os saldos de estoques, imobilizado e "
               "obrigações da incorporada passaram a integrar estas demonstrações a partir "
               "daquela data, o que explica a variação dos saldos comparativos.")
NOTA_MIGRACAO = ("A partir de fevereiro de 2024 a operação de exportação passou a ser conduzida "
                 "pela Araucária Trading Internacional Ltda. A redução da receita e das contas a "
                 "receber em moeda estrangeira decorre dessa migração, e não de retração de "
                 "volume do grupo.")

# A.1 — o comparativo completo de cada empresa (14)
for ent in D.ORDEM:
    extra = NOTA_INCORP if ent == "serraria" else (NOTA_MIGRACAO if ent == "comercial" else None)
    gera(f"bp completo {ent}", R.pdf_balanco, bp, tot, ent, anos_de(ent),
         nome("Balanco Patrimonial", ent, anos_de(ent)), nota_extra=extra)

# A.2 — um segundo comparativo, com OUTRO recorte, para as principais + holding (6)
for ent in ["holding"] + D.PRINCIPAIS:
    a = anos_de(ent)[:2]
    gera(f"bp recorte {ent}", R.pdf_balanco, bp, tot, ent, a,
         nome("Balanco Patrimonial Comparativo", ent, a))

# A.3 — o exercício ISOLADO de cada empresa (14)
for ent in D.ORDEM:
    a = [ultimo_ano(ent)]
    gera(f"bp isolado {ent}", R.pdf_balanco, bp, tot, ent, a,
         nome("Balanco Patrimonial Encerramento", ent, a))


# ===========================================================================
# B. DEMONSTRAÇÕES DO RESULTADO — 20
# ===========================================================================
gera("dre serraria", R.pdf_dre, bp, tot, list(reversed(D.ANOS)),
     nome("Demonstracao do Resultado", "serraria", list(reversed(D.ANOS))))

for ent in GIRO:                                                          # 12
    a = anos_de(ent)
    gera(f"dre {ent}", R.pdf_dre_condensada, bp, tot, ent, a, RECEITA_OUTRAS[ent],
         nome("Demonstracao do Resultado", ent, a))

# O exercício isolado, para as cinco principais (5)
for ent in D.PRINCIPAIS:
    a = [ultimo_ano(ent)]
    if ent == "serraria":
        gera("dre serraria isolada", R.pdf_dre, bp, tot, a,
             nome("Demonstracao do Resultado do Exercicio", ent, a))
    else:
        gera(f"dre isolada {ent}", R.pdf_dre_condensada, bp, tot, ent, a,
             RECEITA_OUTRAS[ent], nome("Demonstracao do Resultado do Exercicio", ent, a))


# ===========================================================================
# C. COMBINADOS — 8 (quatro definitivos e quatro preliminares)
# ===========================================================================
for ano in reversed(D.ANOS):
    gera(f"combinado {ano}", R.pdf_combinado, bp, tot, ano,
         nome("Balanco Patrimonial COMBINADO Grupo Araucaria", None, [ano]))

for ano in reversed(D.ANOS):
    gera(f"combinado preliminar {ano}", R.pdf_combinado, bp, tot, ano,
         nome("Balanco Combinado Grupo Araucaria", None, [ano], "versao preliminar"),
         combinado=B.combinado_preliminar(bp, tot, ano), marca=True,
         titulo_extra="Versão preliminar — anterior à revisão das transações entre partes "
                      "relacionadas")


# ===========================================================================
# D. DFC, DMPL E DVA — 11
# ===========================================================================
for ano in reversed(D.ANOS[1:]):                                          # 3
    gera(f"dfc {ano}", R.pdf_dfc, bp, tot, ano,
         nome("Demonstracao dos Fluxos de Caixa", "serraria", [ano]))

gera("dmpl", R.pdf_dmpl, bp, tot,                                         # 1
     nome("Demonstracao das Mutacoes do Patrimonio Liquido", "serraria", list(D.ANOS)))

for ano in reversed(D.ANOS):                                              # 4
    gera(f"dva {ano}", R.pdf_dva, bp, tot, ano,
         nome("Demonstracao do Valor Adicionado", "serraria", [ano]))

# ===========================================================================
# E. BALANCETES ANALÍTICOS — 20 (as cinco principais × quatro exercícios)
# ===========================================================================
for ent in D.PRINCIPAIS:
    for ano in reversed(D.ANOS):
        gera(f"balancete {ent} {ano}", R.pdf_balancete, bp, ano,
             nome("Balancete Analitico", ent, [ano]), ent)


# ===========================================================================
# F. LIVRO RAZÃO — 5
# ===========================================================================
for ano in reversed(D.ANOS):
    gera(f"razão {ano}", R.pdf_razao, bp, ano,
         nome("Livro Razao Fornecedores", "serraria", [ano]))


# ===========================================================================
# G. FATURAMENTO — 8
# ===========================================================================
gera("faturamento 48m", R.pdf_faturamento,
     nome("Relatorio de Faturamento 48 meses", "serraria", list(D.ANOS)))
gera("fat intragrupo", R.pdf_fat_intragrupo, bp,
     nome("Faturamento Intragrupo Grupo Araucaria", None, list(D.ANOS)))


# ===========================================================================
# H. MAPA DE DÍVIDA E MÚTUOS — 12
# ===========================================================================
for ano in reversed(D.ANOS):                                              # 4
    gera(f"mapa dívida {ano}", R.pdf_mapa_divida, bp, ano,
         nome("Mapa de Divida Bancaria", "serraria", [ano]))
for ano in reversed(D.ANOS):                                              # 4
    gera(f"mútuos {ano}", R.pdf_mutuos, bp, tot, ano,
         nome("Mutuos Intragrupo Grupo Araucaria", None, [ano]))


# ===========================================================================
# I. AGING DE RECEBÍVEIS E DE PAGÁVEIS — 16
# ===========================================================================
NOTA_AR = ("O total corresponde às duplicatas a receber BRUTAS (mercado interno e exportação), "
           "antes das perdas estimadas e antes das operações de antecipação registradas como "
           "redutoras do próprio grupo de contas.")
NOTA_AP = ("O total corresponde a fornecedores nacionais, estrangeiros e títulos vencidos, "
           "EXCLUÍDO o saldo intragrupo.")

for ano in reversed(D.ANOS):                                              # 4
    l, t, v = X.aging_recebiveis(bp, ano)
    gera(f"aging AR {ano}", R.pdf_aging, "AGING DE CONTAS A RECEBER POR CLIENTE",
         D.ENTIDADES["serraria"], X.FAIXAS_AR, l, t, v,
         nome("Aging de Contas a Receber", "serraria", [ano]), "Cliente / sacado",
         "(Valores expressos em milhares de reais — R$ mil)", nota=NOTA_AR, ano=ano)

for ano in reversed(D.ANOS):                                              # 4
    l, t, v = X.aging_pagaveis(bp, ano)
    # UM deles sai do ERP em locale en-US. É situação real, e quebra o parser
    # que troca ponto por vírgula sem olhar.
    us = ano == 2024
    gera(f"aging AP {ano}", R.pdf_aging, "AGING DE CONTAS A PAGAR POR FORNECEDOR",
         D.ENTIDADES["serraria"], X.FAIXAS_AP, l, t, v,
         nome("Aging de Contas a Pagar", "serraria", [ano]), "Fornecedor / credor",
         "Values in thousands of Brazilian Reais (BRL '000)" if us
         else "(Valores expressos em milhares de reais — R$ mil)",
         formato="us" if us else "br",
         nota=("Report generated by ERP module AP-4400 (locale en-US). " if us else "") + NOTA_AP,
         ano=ano)

# ===========================================================================
# J. OS SEIS ANEXOS OPERACIONAIS × QUATRO EXERCÍCIOS — 24
# ===========================================================================
ANEXOS = [
    ("estoques", R.pdf_estoques, "Posicao de Estoques", True),
    ("situação fiscal", R.pdf_situacao_fiscal, "Situacao Fiscal e Parcelamentos", True),
    ("contingências", R.pdf_contingencias, "Contingencias e Processos Judiciais", True),
    ("imobilizado", R.pdf_imobilizado, "Composicao do Imobilizado", True),
    ("folha", R.pdf_folha, "Folha de Pagamento", False),
    ("extratos", R.pdf_extratos, "Extrato Bancario Consolidado", True),
]
for rotulo, fn, titulo, com_bp in ANEXOS:
    for ano in reversed(D.ANOS):
        arq = nome(titulo, "serraria", [ano])
        gera(f"{rotulo} {ano}", fn, *( (bp, ano, arq) if com_bp else (ano, arq) ))


# ===========================================================================
# K. NOTAS, PARECER E OS DOCUMENTOS SEM VALOR MONETÁRIO — 12
# ===========================================================================
SEM_VALOR = []


def sem_valor(arq):
    SEM_VALOR.append(arq)
    return arq


for i in range(2):                                                        # 2
    gera(f"notas {i}", R.pdf_notas, bp, tot,
         nome("Notas Explicativas Grupo Araucaria", None, [2025],
              None if i == 0 else "consolidadas"))

for i in range(2):                                                        # 2
    gera(f"parecer {i}", R.pdf_parecer,
         sem_valor(nome("Relatorio do Auditor Independente", None, [2025],
                        None if i == 0 else "reemitido")))

for i in range(3):                                                        # 3
    gera(f"certidões {i}", R.pdf_certidoes,
         sem_valor(nome("Certidoes Negativas Grupo Araucaria", None, None,
                        f"lote {i + 1}")))

for i in range(2):                                                        # 2
    gera(f"organograma {i}", R.pdf_organograma,
         sem_valor(nome("Organograma Societario Grupo Araucaria", None, None,
                        f"versao {i + 1}")))

for i in range(3):                                                        # 3
    gera(f"contrato social {i}", R.pdf_contrato_social, bp, tot,
         sem_valor(nome("Contrato Social Consolidado", "serraria", None,
                        f"alteracao {i + 8}")))


# ===========================================================================
# L. DEMONSTRAÇÕES CONTÁBEIS COMPLETAS (o jogo de anos anteriores) — 8
# ===========================================================================
for ano in reversed(D.ANOS):                                              # 4
    gera(f"df completa {ano}", R.pdf_df_completa, bp, tot, ano,
         nome("Demonstracoes Contabeis Completas", "serraria", [ano]))


# ===========================================================================
# M. OS QUE CHEGAM COM NOME DE VIDA REAL — 12
#
# A armadilha `nome_de_arquivo_mudo`: a empresa e o período têm de sair do
# CONTEÚDO, porque aqui o nome não é nem pista.
# ===========================================================================
gera("doc1", R.pdf_balanco, bp, tot, "agro", [2023], "Doc1.pdf")
gera("doc2", R.pdf_balanco, bp, tot, "metais", [2023, 2022], "Doc2 (1).pdf")
gera("balanço solto", R.pdf_balanco, bp, tot, "varejo", [2024, 2023],
     "balanço 2024 (1).pdf")
gera("digitalizado 1", R.pdf_balancete, bp, 2025,
     "digitalizado_20260115_0007.pdf", "paineis")
gera("digitalizado 2", R.pdf_balancete, bp, 2023,
     "digitalizado_20260115_0011.pdf", "moveis")
gera("anexo iv", R.pdf_estoques, bp, 2024, "ANEXO IV - planilha final REV3.pdf")
gera("anexo vii", R.pdf_imobilizado, bp, 2023, "ANEXO VII - imobilizado (revisado).pdf")
gera("whatsapp", R.pdf_mapa_divida, bp, 2024, "WhatsApp Image 2026-01-14 at 18.42.11.pdf")
gera("scan", R.pdf_situacao_fiscal, bp, 2024, "scan0042.pdf")
gera("sem nome", R.pdf_dre_condensada, bp, tot, "energia", anos_de("energia"),
     RECEITA_OUTRAS["energia"], "documento (3).pdf")
gera("copia", R.pdf_balanco, bp, tot, "trading", [2025, 2024], "Cópia de balanço final.pdf")
gera("enviado", R.pdf_mutuos, bp, tot, 2023, "enviado pelo contador 12-01.pdf")

# ===========================================================================
# N. AS RE-EMISSÕES — o mesmo período, emitido de novo.
#
# POR QUE ESTA FAMÍLIA É CALCULADA E NÃO ESCRITA. O book tem de ter 190
# documentos (cinco vezes os 38 do `book-canastra`), e as famílias acima crescem
# com o número de EXERCÍCIOS e de EMPRESAS. Quando o histórico passou de quatro
# para cinco anos, elas foram de 183 para 216 sozinhas — e ajustar os laços um a
# um até o total bater de novo é exatamente o tipo de conta que se faz errado em
# silêncio. Aqui o corpo do book é o que é, e esta família fecha a diferença.
#
# Elas não são enchimento vazio: re-emissão do mesmo período é o que mais chega
# em kit de cliente, e é a matéria-prima da armadilha `periodo_fora_de_ordem` —
# o mesmo exercício aparecendo em documentos diferentes, com recortes
# diferentes, sem que nenhum deles esteja errado.
# ===========================================================================
RECEITAS_DE_REEMISSAO = [
    ("Fluxo de Caixa Reemitido", lambda a: (R.pdf_dfc, (bp, tot, a), "serraria"), D.ANOS[1:]),
    ("Mapa de Divida Posicao Revisada", lambda a: (R.pdf_mapa_divida, (bp, a), "serraria"), D.ANOS),
    ("Posicao de Recebiveis por Sacado", lambda a: (_aging_ar, (a,), "serraria"), D.ANOS),
    ("Demonstracoes Contabeis arquivo do escritorio",
     lambda a: (R.pdf_df_completa, (bp, tot, a), "serraria"), D.ANOS),
    ("Balancete Analitico Segunda Via", lambda a: (_balancete, (a,), "serraria"), D.ANOS),
]


def _aging_ar(ano):
    l, t, v = X.aging_recebiveis(bp, ano)
    def fn(arq):
        return R.pdf_aging("POSIÇÃO DE RECEBÍVEIS POR SACADO", D.ENTIDADES["serraria"],
                           X.FAIXAS_AR, l, t, v, arq, "Sacado",
                           "(Valores expressos em milhares de reais — R$ mil)",
                           nota=NOTA_AR, ano=ano)
    return fn


def _balancete(ano):
    return lambda arq: R.pdf_balancete(bp, ano, arq, "paineis")


faltam = 190 - len(feitos)
assert faltam >= 0, (
    f"o corpo do book já passou de 190 documentos ({len(feitos)}): "
    "as famílias acima cresceram e é preciso decidir o que sai, não empurrar o total")

i = 0
while len(feitos) < 190:
    titulo, receita, anos = RECEITAS_DE_REEMISSAO[i % len(RECEITAS_DE_REEMISSAO)]
    ano = anos[(i // len(RECEITAS_DE_REEMISSAO)) % len(anos)]
    alvo = receita(ano)
    arq = nome(titulo, alvo[2], [ano], f"reemissao {i // len(RECEITAS_DE_REEMISSAO) + 2}")
    fn, args = alvo[0], alvo[1]
    if callable(fn) and not args:
        gera(f"reemissão {i}", fn, arq)
    elif fn in (_aging_ar, _balancete):
        gera(f"reemissão {i}", fn(*args), arq)
    else:
        gera(f"reemissão {i}", fn, *args, arq)
    i += 1

print(f"corpo do book: {len(feitos) - faltam} documentos; re-emissões: {faltam}")


R.SEM_VALOR_MONETARIO.update(SEM_VALOR)


# ===========================================================================
# AS CONFERÊNCIAS DO PRÓPRIO GERADOR.
#
# Duas, e as duas existem porque com 190 documentos o erro que importa é o que
# não aparece: um arquivo gerado duas vezes (o segundo sobrescreve o primeiro em
# silêncio, e o kit chega com 189) e um total que deixou de ser 5× o canastra
# sem ninguém notar.
# ===========================================================================
assert len(feitos) == len(set(feitos)), (
    "nome de arquivo repetido — o segundo sobrescreve o primeiro sem dizer nada: "
    + ", ".join(sorted({f for f in feitos if feitos.count(f) > 1})))
assert len(feitos) == 190, f"o book tem de ter 190 documentos (5× o canastra); tem {len(feitos)}"
no_disco = [f for f in os.listdir(R.OUT) if f.lower().endswith(".pdf")]
assert len(no_disco) == 190, (
    f"o diretório tem {len(no_disco)} PDFs e o gerador escreveu 190 — sobrou arquivo de uma "
    "rodada anterior, e um kit com duas vintagens misturadas parece certo e não é")

print(f"{len(feitos)} PDFs gerados em {R.OUT}")


# ---------------------------------------------------------------- GABARITO ---
# O gabarito é o que separa este book de um gerador de PDFs bonitos: sem ele,
# uma rodada não pode ser julgada, só admirada.
ULT = D.ANOS[-1]
dre = X.dre_industria(bp, tot)
fat_linhas, fat_totais = X.faturamento_36m()
contratos, divida_total, juros_total = X.mapa_divida(bp, ULT)
mut_planilha, mut_total_planilha, mut_total_balanco = X.mutuos(bp, tot, ULT)
est_grupos, est_provisao, est_total = X.estoques(bp, ULT)
cont_linhas, cont_provisionado, cont_possivel, cont_remoto = X.contingencias(bp, ULT)
imo_linhas, imo_custo, imo_dep, imo_liquido = X.imobilizado(bp, ULT)
folha_linhas, headcount, folha_anual = X.folha(ULT)
extrato_linhas, extrato_total = X.extratos(bp, ULT)
dfc_linhas, caixa_ini, caixa_fim = X.dfc(bp, tot, ULT)
dmpl_colunas, dmpl_mov = X.dmpl(bp, tot)
dva_geracao, dva_distribuicao, dva_total = X.dva(bp, tot, ULT)

gab = {
    "grupo": D.GRUPO,
    "livro": "book-araucaria",
    "documentos": len(feitos),
    "exercicios": list(D.ANOS),
    "exercicio_retroativo": {
        "ano": D.ANO_RETRO,
        "nota": "Construído para trás a partir de 2022 por regra declarada (dados.RETRO), "
                "e não curado conta a conta como os outros quatro. O que ele prova é que a "
                "SÉRIE tem cinco pontos e direção coerente.",
    },
    "entidades": {k: D.ENTIDADES[k]["razao_social"] for k in D.ENTIDADES},
    "razao_alternativa": {k: v.get("razao_alternativa") for k, v in D.ENTIDADES.items()},
    "cnpj": {k: D.ENTIDADES[k]["cnpj"] for k in D.ENTIDADES},
    "participacao": D.PARTICIPACAO,
    "vigencia": {k: list(D.anos_da_entidade(k)) for k in D.ENTIDADES},
    "eventos_societarios": {k: v["evento"] for k, v in D.ENTIDADES.items() if "evento" in v},
    "balanco_por_entidade": {
        str(ano): {k: {ch: tot[ano][k][ch] for ch in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL")}
                   for k in M.ordem_do_ano(ano)}
        for ano in D.ANOS},
    "combinado": {
        str(ano): {kk: vv for kk, vv in M.combinado(bp, tot, ano).items()
                   if kk in ("ativo", "passivo", "pl", "nci", "elim_invest",
                             "elim_mutuos", "elim_provisao", "pl_holding")}
        for ano in D.ANOS},
    "combinado_preliminar": {
        str(ano): {
            "ativo": B.combinado_preliminar(bp, tot, ano)["ativo"],
            "infla_o_ativo_em": -B.diferenca_preliminar(bp, tot, ano),
            "nota": "Esta versão FECHA (Ativo = Passivo + PL). Conferir o fechamento NÃO "
                    "distingue a preliminar da definitiva.",
        } for ano in D.ANOS},
    "dre_serraria": {str(ano): X.ancoras(dre[ano]) for ano in D.ANOS},
    "receita_bruta_serraria": {str(a): v for a, v in X.RECEITA_BRUTA.items()},
    "resultado_serraria": {str(a): v for a, v in X.resultado_alvo(tot).items()},
    "faturamento_total_R$": {str(a): v for a, v in fat_totais.items()},
    "faturamento_meses": len(fat_linhas),
    "divida_bancaria_R$": divida_total,
    "divida_bancaria_R$mil": X.divida_bancaria(bp, ULT),
    "juros_exercicio_R$": juros_total,
    "mutuos": {"planilha": mut_total_planilha, "balanco": mut_total_balanco,
               "divergencia": mut_total_balanco - mut_total_planilha,
               "nota": "Divergência VERDADEIRA — tem de abrir pendência."},
    "estoques": {"total": est_total, "provisao": est_provisao, "grupos": len(est_grupos)},
    "contingencias": {"provisionado": cont_provisionado, "possivel": cont_possivel,
                      "remoto": cont_remoto},
    "imobilizado": {"custo": imo_custo, "depreciacao": imo_dep, "liquido": imo_liquido},
    "folha": {"headcount": headcount, "custo_anual_R$mil": folha_anual,
              "nota": "A coluna de pessoas NÃO é dinheiro."},
    "extratos_R$": extrato_total,
    "dfc": {"caixa_inicial": caixa_ini, "caixa_final": caixa_fim},
    "dva_total": dva_total,
    "documentos_sem_valor_monetario": sorted(SEM_VALOR),
    "armadilhas": B.resumo(),
    "arquivos": sorted(feitos),
}
with open(f"{R.OUT}/GABARITO.json", "w", encoding="utf-8") as fh:
    json.dump(gab, fh, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------- MÉTRICAS ---
import re
import extrai

metricas, texto_por_arquivo = [], {}
for arquivo in sorted(feitos):
    caminho = f"{R.OUT}/{arquivo}"
    bruto = open(caminho, "rb").read()
    texto = extrai.texto(caminho)
    linhas_texto = [l for l in texto.split("\n") if l.strip()]
    linhas_reais = [l for l in extrai.linhas(caminho) if l.strip()]
    texto_por_arquivo[arquivo] = linhas_reais
    verdade = R.CONTAGEM.get(arquivo, {"linhas_de_conta": 0, "celulas_de_valor": 0,
                                       "contas_distintas": 0})
    metricas.append({
        "arquivo": arquivo,
        "paginas": len(re.findall(rb"/Type\s*/Page[^s]", bruto)),
        "bytes": len(bruto),
        "caracteres": len(texto),
        "linhas_texto": len(linhas_texto),
        "linhas_com_numero": sum(1 for l in linhas_texto if any(ch.isdigit() for ch in l)),
        "linhas_de_conta_verdade": verdade["linhas_de_conta"],
        "celulas_de_valor_verdade": verdade["celulas_de_valor"],
        "contas_distintas_verdade": verdade["contas_distintas"],
    })

with open(f"{R.OUT}/METRICAS.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-araucaria", "documentos": metricas}, fh, indent=2,
              ensure_ascii=False)
with open(f"{R.OUT}/TEXTO_EXTRAIDO.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-araucaria", "documentos": texto_por_arquivo}, fh, indent=1,
              ensure_ascii=False)

print(f"METRICAS.json: {len(metricas)} documentos, "
      f"{sum(m['paginas'] for m in metricas)} páginas, "
      f"{sum(m['linhas_com_numero'] for m in metricas)} linhas com número")


# ------------------------------------------------------------------- GUIA ---
def _mil(v):
    return f"{v:,}".replace(",", ".")


linhas_guia = [
    f"# Guia de teste — {D.GRUPO}",
    "",
    f"**{len(feitos)} documentos · {len(D.ENTIDADES)} empresas · {len(D.ANOS)} exercícios "
    f"({D.ANOS[0]} a {D.ANOS[-1]}) · {sum(m['paginas'] for m in metricas)} páginas · "
    f"{sum(m['linhas_com_numero'] for m in metricas):,} linhas com número**".replace(",", "."),
    "",
    "> Gerado por `PYTHONPATH=. python3 gerar.py`. **Determinístico no conteúdo**: rodar duas",
    "> vezes dá o mesmo texto em todos os 190 PDFs e o mesmo `GABARITO.json` — medido, comparando",
    "> o hash do `TEXTO_EXTRAIDO.json` entre duas rodadas. Os arquivos **não** são idênticos byte",
    "> a byte, porque o reportlab carimba data de criação e ID em cada PDF; isso vale também para",
    "> os dois books anteriores. O que o gabarito exige é a primeira propriedade, não a segunda.",
    "",
    "## O que este book é, e o que ele não é",
    "",
    "É o terceiro book do repositório e o primeiro cujo objetivo declarado é ser **confuso**. O",
    "`book-vertentes` representa o caso em que a extração é fiel e nada deve abrir pendência; o",
    "`book-canastra` representa a dificuldade de um kit real bem organizado. Este representa o kit",
    "de um grupo que passou por uma **reestruturação societária no meio do período** e que, por",
    "isso, contradiz a si mesmo em vários pontos sem que nenhum documento esteja errado.",
    "",
    "A distinção que sustenta o book inteiro:",
    "",
    "> **BAGUNÇADO NÃO É INCOMPLETO, E NÃO É INCONSISTENTE.**",
    "",
    "Cada balanço fecha. O combinado fecha nos cinco exercícios. Cada anexo lê o balanço em vez de",
    "digitar o próprio total. O que é bagunçado é a **leitura** — nomes, versões, escalas, recortes",
    "e vigências —, não a aritmética. Conflito sem resposta certa não é teste, é ruído; e ruído não",
    "mede nada, porque qualquer saída passa.",
    "",
    "## A história do grupo",
    "",
    f"O {D.GRUPO} é um grupo madeireiro do Paraná com {len(D.ENTIDADES)} empresas. Em "
    f"{D.ANOS[0]} está no pico: madeira serrada em alta e exportação aquecida. A partir de "
    f"{D.ANOS[1]} o preço do pinus serrado cai, a margem comprime e o grupo passa a operar com",
    "capital de terceiros. No meio do caminho acontecem três eventos societários que são a fonte",
    "principal da confusão do kit:",
    "",
]
for k, e in D.ENTIDADES.items():
    if "evento" in e:
        anos = D.anos_da_entidade(k)
        linhas_guia.append(f"- **{e['razao_social']}** — {e['evento']} "
                           f"Aparece nos exercícios de {anos[0]} a {anos[-1]}.")
linhas_guia += [
    "",
    "O resultado, medido: o patrimônio líquido combinado vai de "
    + _mil(M.combinado(bp, tot, D.ANOS[0])["pl"]) + " para "
    + _mil(M.combinado(bp, tot, D.ANOS[-1])["pl"]) + " (R$ mil) em cinco exercícios.",
    "",
    "| Exercício | Ativo combinado | Passivo | PL | Não controladores |",
    "|---|---:|---:|---:|---:|",
]
for ano in D.ANOS:
    c = M.combinado(bp, tot, ano)
    linhas_guia.append(f"| {ano} | {_mil(c['ativo'])} | {_mil(c['passivo'])} | "
                       f"{_mil(c['pl'])} | {_mil(c['nci'])} |")

linhas_guia += [
    "",
    "## O exercício de 2021 é DERIVADO, e isso muda como ele deve ser lido",
    "",
    "Nos exercícios de 2022 a 2025 cada saldo é uma escolha curada, conta a conta. O de **2021 é",
    "construído para trás** a partir de 2022, por uma regra declarada grupo de contas a grupo de",
    "contas (`RETRO`, em `dados.py`): a dívida era 0,58 do que viria a ser, as provisões 0,40, o",
    "giro operacional 1,08. Ele fecha como os outros e é internamente coerente, mas o que ele prova",
    "é que a **série tem cinco pontos e uma direção**, não que cada saldo individual seja",
    "interessante. O que ele acrescenta é decisivo assim mesmo: com quatro anos, o kit já começava",
    "na descida; com cinco, o **pico fica dentro da janela**.",
    "",
    "Duas outras linhas do book são declaradas e não medidas, pelo mesmo motivo (não há exercício",
    f"anterior a {D.ANOS[0]} para variar contra): o resultado e os dividendos do primeiro",
    "exercício, na DMPL.",
    "",
    "## As armadilhas deliberadas",
    "",
    f"São **{len(B.ARMADILHAS)}**, e cada uma tem resposta certa. Uma armadilha sem resposta certa",
    "seria decoração.",
    "",
]
for i, a in enumerate(B.ARMADILHAS, 1):
    linhas_guia += [
        f"### {i}. `{a['chave']}`",
        "",
        f"**O que se vê.** {a['o_que']}",
        "",
        f"**Por que acontece.** {a['porque']}",
        "",
        f"**Resposta certa.** {a['resposta']}",
        "",
    ]

linhas_guia += [
    "## O número que a versão preliminar do combinado infla",
    "",
    "A armadilha mais cara do book, com o valor exato que a rodada tem de reencontrar:",
    "",
    "| Exercício | Combinado definitivo | Versão preliminar | Diferença |",
    "|---|---:|---:|---:|",
]
for ano in D.ANOS:
    d = M.combinado(bp, tot, ano)["ativo"]
    p = B.combinado_preliminar(bp, tot, ano)["ativo"]
    linhas_guia.append(f"| {ano} | {_mil(d)} | {_mil(p)} | **+{_mil(p - d)}** |")

linhas_guia += [
    "",
    "As duas versões **fecham**. Conferir `Ativo = Passivo + PL` não distingue uma da outra — só o",
    "quadro de eliminações distingue, e é por isso que ele é impresso por extenso nos dois.",
    "",
    "## Os documentos que NÃO podem render linha financeira",
    "",
    "Zero linha é o resultado **certo** nestes, não extração falha:",
    "",
]
for arq in sorted(SEM_VALOR):
    linhas_guia.append(f"- `{arq}`")

linhas_guia += [
    "",
    "As notas explicativas e o relatório do auditor carregam **fato material em texto** — covenant",
    "rompido, ressalva, incerteza sobre continuidade operacional. Isso é outro canal (`0148`/`0149`",
    "no banco), e não pendência de extração.",
    "",
    "## Como conferir uma rodada",
    "",
    "1. O `GABARITO.json` traz o balanço de cada empresa em cada exercício, o combinado (definitivo",
    "   e preliminar), as âncoras da DRE, os totais de cada anexo e as armadilhas com a resposta.",
    "2. O `METRICAS.json` traz, por documento, páginas, caracteres e linhas com número — é o insumo",
    "   da estimativa de custo (`node ../../n8n/medir-custo-book.mjs`).",
    "3. O `TEXTO_EXTRAIDO.json` traz o texto real de cada PDF, agrupado por linha, para medir a",
    "   régua de cobertura sem reimplementar leitura de PDF em outra linguagem.",
    "",
    "**A pergunta que este book existe para responder não é «a extração acertou os números?» — os",
    "dois books anteriores já respondem essa. É «o sistema percebe que dois documentos do mesmo",
    "período discordam, e escolhe o certo dizendo por quê?».**",
    "",
]

with open(f"{R.OUT}/GUIA_DE_TESTE.md", "w", encoding="utf-8") as fh:
    fh.write("\n".join(linhas_guia) + "\n")
print(f"GABARITO.json e GUIA_DE_TESTE.md gravados em {R.OUT}")
