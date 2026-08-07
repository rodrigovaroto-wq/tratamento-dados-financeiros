# -*- coding: utf-8 -*-
"""Renderização do book CANASTRA em PDF.

A aparência importa porque o insumo do pipeline é a PÁGINA, não o dicionário: é
a diagramação que produz coluna encavalada, cabeçalho repetido, rodapé colado no
número e rótulo quebrado em duas linhas — os defeitos de leitura que só aparecem
quando existe um documento de verdade.

As bagunças de FORMATO ficam concentradas aqui de propósito (o dado em si é
íntegro e fecha; quem varia é como ele é impresso):

  • escala por documento — R$ mil, reais, quantidade física, pessoas;
  • negativo entre parênteses, com sinal, ou pela natureza D/C;
  • separador decimal brasileiro em quase tudo e ANGLO em um documento, que é o
    que um ERP exportando em `en-US` entrega no meio de um kit em português;
  • número de página, carimbo de recebido e marca d'água por cima do conteúdo.
"""

import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

import dados as D
import demonstracoes as X
import motor as M

OUT = os.path.join(os.path.dirname(__file__), "pdf")
os.makedirs(OUT, exist_ok=True)

RODAPE_SINTETICO = ("Documento sintético, gerado para teste de sistema. Não corresponde a "
                    "empresa, pessoa ou fato real.")
CONTADOR = "Rita M. Andrade — Contadora — CRC 1MG-198.442/O-7"
DIRETOR = "Paulo Sérgio Canastra — Diretor Presidente — CPF 987.654.321-00"

ST_TIT = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=11, alignment=TA_CENTER, leading=14)
ST_SUB = ParagraphStyle("s", fontName="Helvetica", fontSize=8.5, alignment=TA_CENTER, leading=11)
ST_NOTA = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=7, leading=9)
ST_TXT = ParagraphStyle("p", fontName="Helvetica", fontSize=8.5, leading=12, alignment=TA_JUSTIFY)
ST_H2 = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=9, leading=13, spaceBefore=6)
ST_CEL = ParagraphStyle("c", fontName="Helvetica", fontSize=6.6, leading=8)
ST_CELD = ParagraphStyle("cd", fontName="Helvetica", fontSize=6.6, leading=8, alignment=TA_RIGHT)


# --------------------------------------------------------------- FORMATAÇÃO --
def num(v, casas=0, formato="br", dash_zero=False, sinal_menos=False):
    """Formata um número como o documento o imprime.

    `formato="us"` existe para UM documento do book: sistema que exporta em
    `en-US` no meio de um kit em português é situação real, e ela quebra o
    parser ingênuo que troca ponto por vírgula sem olhar."""
    if v is None:
        return ""
    if v == 0 and dash_zero:
        return "-"
    s = f"{abs(v):,.{casas}f}"
    if formato == "br":
        s = s.replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    if v < 0:
        return f"-{s}" if sinal_menos else f"({s})"
    return s


def pct(v, casas=1, formato="br"):
    s = f"{v:.{casas}f}"
    return (s.replace(".", ",") if formato == "br" else s) + "%"


def cabecalho(entidade, cnpj, titulo, periodo, escala, extra=None):
    el = [Paragraph(entidade, ST_TIT)]
    if cnpj:
        el.append(Paragraph(f"CNPJ {cnpj}", ST_SUB))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(titulo, ST_TIT))
    el.append(Paragraph(periodo, ST_SUB))
    if escala:
        el.append(Paragraph(escala, ST_SUB))
    if extra:
        el.append(Paragraph(extra, ST_SUB))
    el.append(Spacer(1, 4 * mm))
    return el


def _rodape_pagina(canvas, doc_):
    canvas.saveState()
    canvas.setFont("Helvetica", 6.5)
    canvas.setFillColorRGB(.35, .35, .35)
    canvas.drawRightString(doc_.pagesize[0] - 15 * mm, 8 * mm, f"Página {canvas.getPageNumber()}")
    canvas.drawString(15 * mm, 8 * mm, RODAPE_SINTETICO)
    canvas.restoreState()


def _marca_dagua(canvas, doc_):
    _rodape_pagina(canvas, doc_)
    canvas.saveState()
    canvas.setFont("Helvetica-Bold", 46)
    canvas.setFillColorRGB(.86, .86, .86)
    canvas.translate(doc_.pagesize[0] / 2, doc_.pagesize[1] / 2)
    canvas.rotate(38)
    canvas.drawCentredString(0, 0, "CÓPIA NÃO AUDITADA")
    canvas.restoreState()


def doc(nome_arquivo, paisagem=False, marca=False):
    d = SimpleDocTemplate(
        os.path.join(OUT, nome_arquivo),
        pagesize=landscape(A4) if paisagem else A4,
        leftMargin=14 * mm, rightMargin=14 * mm, topMargin=13 * mm, bottomMargin=15 * mm,
        title=nome_arquivo.replace(".pdf", ""), author="Sistema sintético de teste",
    )
    d._decorador = _marca_dagua if marca else _rodape_pagina
    return d


def build(d, elementos):
    d.build(elementos, onFirstPage=d._decorador, onLaterPages=d._decorador)


def _tab(linhas, larguras, estilos_extra=(), fonte=7.2, repeat=1):
    t = Table(linhas, colWidths=larguras, repeatRows=repeat)
    est = [("FONTSIZE", (0, 0), (-1, -1), fonte),
           ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
           ("FONTNAME", (0, 0), (-1, repeat - 1), "Helvetica-Bold"),
           ("LINEBELOW", (0, repeat - 1), (-1, repeat - 1), 0.7, colors.black),
           ("TOPPADDING", (0, 0), (-1, -1), 1.1),
           ("BOTTOMPADDING", (0, 0), (-1, -1), 1.1),
           ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]
    est.extend(estilos_extra)
    t.setStyle(TableStyle(est))
    return t


def _assina(el, extra=None, contador=CONTADOR, diretor=DIRETOR):
    el.append(Spacer(1, 5 * mm))
    if extra:
        el.append(Paragraph(extra, ST_NOTA))
        el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("_______________________________________", ST_NOTA))
    el.append(Paragraph(contador, ST_NOTA))
    if diretor:
        el.append(Spacer(1, 1.5 * mm))
        el.append(Paragraph(diretor, ST_NOTA))


# ------------------------------------------------------------------ BALANÇO --
def tabela_balanco(bp, tot, ent, anos, largura_rot=None, formato="br"):
    """Balanço comparativo com UMA COLUNA POR EXERCÍCIO (aqui podem ser três).

    Conta que não existe num exercício sai com a célula VAZIA — não com zero."""
    n = len(anos)
    largura_rot = largura_rot or (182 - 26 * n) * mm
    linhas, estilos = [], []
    linhas.append([""] + [f"31/12/{a}" for a in anos])
    estilos.extend([("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("LINEBELOW", (0, 0), (-1, 0), 0.7, colors.black),
                    ("ALIGN", (1, 0), (-1, -1), "RIGHT")])
    i = 1

    def add(rot, valores, estilo=None, indent=0):
        nonlocal i
        linhas.append(["  " * indent + rot] + [num(v, formato=formato) for v in valores])
        if estilo == "grupo":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.90, .90, .90))])
        elif estilo == "secao":
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        elif estilo == "sub":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Oblique"),
                            ("TEXTCOLOR", (0, i), (-1, i), colors.Color(.25, .25, .25))])
        elif estilo == "total":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1

    def contas(ano, secao, sub):
        return {r: v for r, v in bp[ano][ent][secao].get(sub, [])}

    def secoes(lista):
        for sec, label in lista:
            add(label, [M.soma_folhas(bp[a][ent][sec]) for a in anos], "secao")
            subs = []
            for a in anos:
                for s in bp[a][ent][sec]:
                    if s not in subs:
                        subs.append(s)
            for sub in subs:
                por_ano = {a: contas(a, sec, sub) for a in anos}
                add(sub, [sum(por_ano[a].values()) if por_ano[a] else None for a in anos], "sub", 1)
                rotulos = []
                for a in anos:
                    for r in por_ano[a]:
                        if r not in rotulos:
                            rotulos.append(r)
                for r in rotulos:
                    add(r, [por_ano[a].get(r) for a in anos], None, 2)

    add("ATIVO", [tot[a][ent]["ATIVO"] for a in anos], "grupo")
    secoes([("AC", "Ativo Circulante"), ("ANC", "Ativo Não Circulante")])
    add("TOTAL DO ATIVO", [tot[a][ent]["ATIVO"] for a in anos], "total")
    linhas.append([""] * (n + 1))
    i += 1
    add("PASSIVO E PATRIMÔNIO LÍQUIDO", [tot[a][ent]["PASSIVO_PL"] for a in anos], "grupo")
    secoes([("PC", "Passivo Circulante"), ("PNC", "Passivo Não Circulante")])
    add("Patrimônio Líquido", [tot[a][ent]["PL"] for a in anos], "secao")
    subs_pl = []
    for a in anos:
        for s in bp[a][ent]["PL"]:
            if s not in subs_pl:
                subs_pl.append(s)
    for sub in subs_pl:
        por_ano = {a: contas(a, "PL", sub) for a in anos}
        add(sub, [sum(por_ano[a].values()) if por_ano[a] else None for a in anos], "sub", 1)
        rotulos = []
        for a in anos:
            for r in por_ano[a]:
                if r not in rotulos:
                    rotulos.append(r)
        for r in rotulos:
            add(r, [por_ano[a].get(r) for a in anos], None, 2)
    add("TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO",
        [tot[a][ent]["PASSIVO_PL"] for a in anos], "total")

    t = Table(linhas, colWidths=[largura_rot] + [26 * mm] * n, repeatRows=1)
    estilos.extend([("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
                    ("FONTSIZE", (0, 0), (-1, -1), 7.0),
                    ("TOPPADDING", (0, 0), (-1, -1), 1.0),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 1.0),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE")])
    t.setStyle(TableStyle(estilos))
    return t


def pdf_balanco(bp, tot, ent, anos, arquivo, nota_extra=None, marca=False, formato="br"):
    e = D.ENTIDADES[ent]
    d = doc(arquivo, marca=marca)
    per = ("Exercícios encerrados em " +
           " e em ".join(", ".join(f"31 de dezembro de {a}" for a in anos).rsplit(", ", 1)))
    el = cabecalho(e["razao_social"], e["cnpj"], "BALANÇO PATRIMONIAL", per,
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(tabela_balanco(bp, tot, ent, anos, formato=formato))
    el.append(Spacer(1, 4 * mm))
    if nota_extra:
        el.append(Paragraph(nota_extra, ST_NOTA))
        el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("As notas explicativas são parte integrante das demonstrações contábeis.",
                        ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ---------------------------------------------------------------- COMBINADO --
def pdf_combinado(bp, tot, ano, arquivo):
    """Uma coluna por empresa + Eliminações + Combinado.

    A coluna "Eliminações" NÃO é uma empresa — se o extrator a tratar como
    entidade, o combinado passa a ter sete empresas e uma delas com o sinal
    trocado. É a armadilha central deste documento."""
    c = M.combinado(bp, tot, ano)
    ordem = c["ordem"]
    curtos = {"holding": "Canastra Part.", "industria": "Canastra Ind.",
              "comercial": "Canastra Com.", "transportes": "CN Transportes",
              "agro": "Canastra Agro", "imob": "Canastra SPE"}
    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.GRUPO, None, "BALANÇO PATRIMONIAL COMBINADO",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)",
                   "Elaborado para fins gerenciais — não auditado")

    cab = [""] + [curtos[k] for k in ordem] + ["Eliminações", "Combinado"]
    linhas, estilos = [cab], []
    i = 1

    def add(rot, valores, elim, comb, negrito=False, fundo=False):
        nonlocal i
        linhas.append([rot] + [num(v) for v in valores] + [num(elim), num(comb)])
        if negrito:
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        if fundo:
            estilos.append(("BACKGROUND", (0, i), (-1, i), colors.Color(.92, .92, .92)))
        i += 1

    ac = [tot[ano][k]["AC"] for k in ordem]
    anc = [tot[ano][k]["ANC"] for k in ordem]
    add("Ativo Circulante", ac, -c["elim_mutuos"], sum(ac) - c["elim_mutuos"])
    add("Ativo Não Circulante", anc, -c["elim_invest"], sum(anc) - c["elim_invest"])
    add("TOTAL DO ATIVO", [tot[ano][k]["ATIVO"] for k in ordem],
        -(c["elim_mutuos"] + c["elim_invest"]), c["ativo"], negrito=True, fundo=True)
    linhas.append([""] * len(cab))
    i += 1
    pc = [tot[ano][k]["PC"] for k in ordem]
    pnc = [tot[ano][k]["PNC"] for k in ordem]
    add("Passivo Circulante", pc, -c["elim_mutuos"], sum(pc) - c["elim_mutuos"])
    add("Passivo Não Circulante", pnc, -c["elim_provisao"], sum(pnc) - c["elim_provisao"])
    add("Patrimônio Líquido dos controladores", [tot[ano][k]["PL"] for k in ordem],
        -(sum(tot[ano][k]["PL"] for k in ordem) - c["pl_holding"] - c["nci"]) - c["nci"],
        c["pl_holding"])
    add("Participação de não controladores", [None] * len(ordem), c["nci"], c["nci"])
    add("TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO",
        [tot[ano][k]["PASSIVO_PL"] for k in ordem],
        c["passivo"] + c["pl"] - sum(tot[ano][k]["PASSIVO_PL"] for k in ordem),
        c["passivo"] + c["pl"], negrito=True, fundo=True)

    el.append(_tab(linhas, [62 * mm] + [26 * mm] * (len(cab) - 1), estilos, fonte=7.4))
    el.append(Spacer(1, 4 * mm))
    detalhe = [["Eliminações do combinado", "Valor"]]
    for rot, v in c["elim"]:
        detalhe.append([rot, num(-v)])
    detalhe.append(["Investimentos avaliados por equivalência patrimonial", num(-c["elim_invest"])])
    detalhe.append(["Provisão para passivo a descoberto em controladas", num(-c["elim_provisao"])])
    el.append(_tab(detalhe, [120 * mm, 30 * mm], fonte=7.2))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — A coluna <b>Eliminações</b> não representa entidade jurídica: registra a exclusão "
        "de saldos recíprocos entre as empresas do grupo e dos investimentos avaliados por "
        "equivalência patrimonial. A participação de não controladores refere-se aos 35% do "
        "capital da CN Transportes e Logística Ltda. detidos por terceiros.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------------- DRE ---
def pdf_dre(bp, tot, anos, arquivo):
    dre = X.dre_industria(bp, tot)
    e = D.ENTIDADES["industria"]
    d = doc(arquivo)
    per = ("Exercícios encerrados em " +
           " e em ".join(", ".join(f"31 de dezembro de {a}" for a in anos).rsplit(", ", 1)))
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO",
                   per, "(Valores expressos em milhares de reais — R$ mil)")

    # A ordem das linhas é a do exercício mais recente; anos anteriores casam
    # pelo RÓTULO — e linha que só existe num ano fica vazia nos outros, que é
    # o que acontece quando a empresa reconhece impairment só num exercício.
    base = dre[anos[0]]
    linhas, estilos = [[""] + [str(a) for a in anos]], []
    i = 1
    for rot, _v, tipo in base:
        valores = []
        for a in anos:
            achado = [v for r, v, t in dre[a] if r == rot]
            valores.append(achado[0] if achado else None)
        linhas.append([rot] + [num(v) for v in valores])
        if tipo == "ancora":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
        elif tipo == "subtotal":
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        i += 1
    # Linhas que existem em outro exercício e não no mais recente (impairment).
    ja = {r for r, _, _ in base}
    for a in anos[1:]:
        for rot, _v, tipo in dre[a]:
            if rot in ja:
                continue
            ja.add(rot)
            valores = [next((v for r, v, t in dre[x] if r == rot), None) for x in anos]
            linhas.append([rot] + [num(v) for v in valores])
            i += 1

    el.append(_tab(linhas, [92 * mm] + [29 * mm] * len(anos), estilos, fonte=7.2))
    el.append(Spacer(1, 4 * mm))
    a25 = X.ancoras(dre[anos[0]])
    el.append(Paragraph(
        f"Nota — A margem bruta do exercício de {anos[0]} foi de "
        f"{pct(a25['LUCRO BRUTO'] / a25['RECEITA OPERACIONAL LÍQUIDA'] * 100)} "
        f"(contra {pct(X.ancoras(dre[anos[-1]])['LUCRO BRUTO'] / X.ancoras(dre[anos[-1]])['RECEITA OPERACIONAL LÍQUIDA'] * 100)} "
        f"em {anos[-1]}), refletindo o aumento do custo do papel kraft sem repasse "
        "correspondente ao preço de venda.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


def pdf_dre_condensada(bp, tot, ent, anos, receita, arquivo):
    """DRE resumida das demais empresas: 12 linhas, resultado amarrado ao PL."""
    e = D.ENTIDADES[ent]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO",
                   "Exercícios encerrados em " + " e em ".join(f"31 de dezembro de {a}" for a in anos),
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas, estilos = [[""] + [str(a) for a in anos]], []
    blocos = X.dre_condensada(bp, tot, ent, receita, anos)
    i = 1
    for rot, valores, tipo in blocos:
        linhas.append([rot] + [num(v) for v in valores])
        if tipo == "ancora":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1
    el.append(_tab(linhas, [100 * mm] + [30 * mm] * len(anos), estilos, fonte=7.6))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------------- DFC ---
def pdf_dfc(bp, tot, ano, arquivo):
    linhas_dfc, ini, fim = X.dfc(bp, tot, ano)
    e = D.ENTIDADES["industria"]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"],
                   "DEMONSTRAÇÃO DOS FLUXOS DE CAIXA — MÉTODO INDIRETO",
                   f"Exercício encerrado em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas, estilos = [["", str(ano)]], []
    i = 1
    for rot, v, tipo in linhas_dfc:
        linhas.append([rot, num(v)])
        if tipo == "ancora":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
        elif tipo == "subtotal":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1
    el.append(_tab(linhas, [130 * mm, 32 * mm], estilos, fonte=7.6))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        f"Nota — O saldo final de caixa e equivalentes de {num(fim)} corresponde ao subgrupo "
        f"Disponível do balanço patrimonial em 31/12/{ano} (saldo inicial de {num(ini)}).", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# -------------------------------------------------------------------- DMPL ---
def pdf_dmpl(bp, tot, arquivo):
    colunas, movimentos = X.dmpl(bp, tot)
    e = D.ENTIDADES["industria"]
    d = doc(arquivo, paisagem=True)
    el = cabecalho(e["razao_social"], e["cnpj"],
                   "DEMONSTRAÇÃO DAS MUTAÇÕES DO PATRIMÔNIO LÍQUIDO",
                   "Exercícios encerrados em 31 de dezembro de 2023, 2024 e 2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas, estilos = [[""] + colunas], []
    i = 1
    for rot, valores, tipo in movimentos:
        linhas.append([rot] + [num(v, dash_zero=True) for v in valores])
        if tipo == "saldo":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
        i += 1
    el.append(_tab(linhas, [96 * mm] + [32 * mm] * len(colunas), estilos, fonte=7.6))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        "Nota — As linhas <b>SALDOS EM 31 DE DEZEMBRO DE ...</b> são posições acumuladas, e não "
        "movimentações do exercício. A realização da reserva de lucros a realizar em 2024 é "
        "transferência entre contas do próprio patrimônio líquido e não afeta o total.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------------- DVA ---
def pdf_dva(bp, tot, ano, arquivo):
    geracao, distribuicao, total = X.dva(bp, tot, ano)
    e = D.ENTIDADES["industria"]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DO VALOR ADICIONADO",
                   f"Exercício encerrado em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas, estilos = [["", str(ano)]], []
    i = 1
    for rot, v, tipo in geracao:
        linhas.append([rot, num(v)])
        if tipo == "ancora":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
        i += 1
    linhas.append(["", ""])
    i += 1
    linhas.append(["DISTRIBUIÇÃO DO VALOR ADICIONADO", num(total)])
    estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
    i += 1
    for rot, v in distribuicao:
        linhas.append([rot, num(v)])
        i += 1
    el.append(_tab(linhas, [130 * mm, 32 * mm], estilos, fonte=7.6))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — O valor adicionado distribuído iguala o produzido por construção; a remuneração "
        "de capitais próprios é negativa por corresponder ao prejuízo do exercício.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------------- FATURAMENTO ---
def pdf_faturamento(arquivo):
    """36 meses em REAIS, com colunas NÃO MONETÁRIAS ao lado (pedidos e ticket
    médio). A ordem é cronológica; ordenar por texto embaralha os meses."""
    linhas_fat, totais = X.faturamento_36m()
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "RELATÓRIO DE FATURAMENTO — ÚLTIMOS 36 MESES",
                   "Janeiro de 2023 a dezembro de 2025",
                   "Faturamento e ticket médio em REAIS (R$); pedidos em quantidade")
    linhas = [["Competência", "Faturamento (R$)", "Pedidos (qtde)", "Ticket médio (R$)"]]
    estilos = []
    i = 1
    for ano in D.ANOS:
        for a, mes, v, ped, ticket in linhas_fat:
            if a != ano:
                continue
            linhas.append([f"{mes}/{ano}", num(v, 2), f"{ped:,}".replace(",", "."), num(ticket, 2)])
            i += 1
        linhas.append([f"TOTAL DE {ano}", num(totais[ano], 2), "", ""])
        estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                        ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1
    el.append(_tab(linhas, [44 * mm, 44 * mm, 34 * mm, 34 * mm], estilos, fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — As colunas <b>Pedidos</b> e <b>Ticket médio</b> não são valores de demonstração "
        "contábil: a primeira é quantidade e a segunda é razão entre faturamento e pedidos. O "
        "faturamento está em REAIS, enquanto as demonstrações contábeis do grupo estão em R$ mil.",
        ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


def pdf_fat_intragrupo(bp, arquivo):
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "FATURAMENTO ENTRE EMPRESAS DO GRUPO",
                   "Exercícios de 2023, 2024 e 2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Exercício", "Empresa emitente", "Empresa tomadora", "Natureza", "Valor"]]
    estilos = []
    i = 1
    for ano, itens in X.faturamento_intragrupo(bp):
        for emit, tom, nat, v in itens:
            linhas.append([str(ano), emit, tom, nat, num(v)])
            i += 1
        linhas.append(["", "", "", f"Total de {ano}", num(sum(v for *_x, v in itens))])
        estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        i += 1
    el.append(_tab(linhas, [18 * mm, 48 * mm, 44 * mm, 44 * mm, 26 * mm], estilos, fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — Estes saldos são eliminados no balanço combinado. O faturamento intragrupo "
        "compõe a receita bruta de cada emitente individualmente.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# ------------------------------------------------------------- MAPA DÍVIDA ---
def pdf_mapa_divida(bp, ano, arquivo):
    contratos, total, juros = X.mapa_divida(bp, ano)
    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "MAPA DE ENDIVIDAMENTO BANCÁRIO",
                   f"Posição em 31 de dezembro de {ano}",
                   "Valores em REAIS (R$), salvo a coluna de saldo em moeda estrangeira")
    cab = ["Instituição", "Modalidade", "Contrato", "Vencimento", "Taxa",
           "Saldo devedor (R$)", "Saldo (US$)", "Juros do exercício (R$)", "Situação"]
    linhas, estilos = [cab], []
    i = 1
    for c in contratos:
        linhas.append([
            Paragraph(c["banco"], ST_CEL), Paragraph(c["modalidade"], ST_CEL),
            Paragraph(c["contrato"], ST_CEL), c["vencimento"], c["taxa"],
            num(c["saldo"], 2), num(c["saldo_usd"], 2) if c["saldo_usd"] else "-",
            num(c["juros"], 2), Paragraph(c["situacao"], ST_CEL),
        ])
        if "Vencido" in c["situacao"]:
            estilos.append(("TEXTCOLOR", (0, i), (-1, i), colors.Color(.55, 0, 0)))
        i += 1
    linhas.append(["TOTAL", "", "", "", "", num(total, 2), "", num(juros, 2), ""])
    estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black)])
    el.append(_tab(linhas, [38 * mm, 34 * mm, 28 * mm, 20 * mm, 25 * mm, 32 * mm, 22 * mm,
                            30 * mm, 34 * mm], estilos, fonte=6.6))
    el.append(Spacer(1, 3 * mm))
    cambio = X.CAMBIO_FECHAMENTO[ano]
    el.append(Paragraph(
        f"Nota 1 — O contrato ACC-2024-090.771 é denominado em DÓLAR DOS ESTADOS UNIDOS. A coluna "
        f"<b>Saldo (US$)</b> traz o principal na moeda de origem; o equivalente em reais foi "
        f"convertido pela taxa de fechamento de R$ {num(cambio, 4)}/US$. <b>As duas colunas não "
        f"devem ser somadas.</b>", ST_NOTA))
    el.append(Paragraph(
        "Nota 2 — Os contratos CG-2021-884.117 e CG-2022-901.554 tiveram vencimento antecipado "
        "declarado pelo credor em razão do descumprimento do índice de cobertura de juros "
        "(EBITDA/despesa financeira mínimo de 1,5x) apurado no encerramento do exercício. Os "
        "saldos foram reclassificados do passivo não circulante para o circulante.", ST_NOTA))
    el.append(Paragraph(
        "Nota 3 — Os valores desta planilha estão em REAIS; as demonstrações contábeis do grupo "
        "estão expressas em MILHARES de reais.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# ----------------------------------------------------------------- MÚTUOS ---
def pdf_mutuos(bp, tot, ano, arquivo):
    saldos, total_planilha, total_balanco = X.mutuos(bp, tot, ano)
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Mutuante", "Mutuária", "Saldo devedor"]]
    for a, b, v in saldos:
        linhas.append([Paragraph(a, ST_CEL), Paragraph(b, ST_CEL), num(v)])
    linhas.append(["", "TOTAL", num(total_planilha)])
    el.append(_tab(linhas, [66 * mm, 78 * mm, 30 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)],
                   fonte=7.4))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — Os mútuos são remunerados a 100% do CDI e não têm vencimento contratado. "
        "A controladora tem a faculdade de converter os saldos em aporte de capital.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# ------------------------------------------------------------------ AGING ---
def pdf_aging(titulo, entidade, faixas, linhas_aging, total, vencido, arquivo,
              rotulo_coluna, escala, formato="br", nota=None):
    d = doc(arquivo, paisagem=True)
    el = cabecalho(entidade["razao_social"], entidade["cnpj"], titulo,
                   "Posição em 31 de dezembro de 2025", escala)
    cab = [rotulo_coluna] + faixas + ["Total", "% do total"]
    linhas, estilos = [cab], []
    i = 1
    for nome, valores, subtotal in linhas_aging:
        linhas.append([Paragraph(nome, ST_CEL)] + [num(v, formato=formato) for v in valores]
                      + [num(subtotal, formato=formato), pct(subtotal / total * 100, formato=formato)])
        i += 1
    totais_faixa = [sum(l[1][k] for l in linhas_aging) for k in range(len(faixas))]
    linhas.append(["TOTAL"] + [num(v, formato=formato) for v in totais_faixa]
                  + [num(total, formato=formato), pct(100.0, formato=formato)])
    estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black)])
    larg = [64 * mm] + [26 * mm] * len(faixas) + [28 * mm, 20 * mm]
    el.append(_tab(linhas, larg, estilos, fonte=6.8))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        f"Vencido (todas as faixas após o vencimento): {num(vencido, formato=formato)} — "
        f"{pct(vencido / total * 100, formato=formato)} da carteira.", ST_NOTA))
    if nota:
        el.append(Paragraph(nota, ST_NOTA))
    el.append(Paragraph(
        "A coluna <b>% do total</b> é percentual e não valor monetário.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# --------------------------------------------------------------- ESTOQUES ---
def pdf_estoques(bp, ano, arquivo):
    grupos, provisao, total = X.estoques(bp, ano)
    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "POSIÇÃO DE ESTOQUES POR ITEM",
                   f"Posição em 31 de dezembro de {ano}",
                   "Valor em R$ mil; quantidade na unidade indicada; custo unitário em R$")
    linhas, estilos = [["Item", "Unidade", "Quantidade", "Valor (R$ mil)", "Custo unitário (R$)"]], []
    i = 1
    for grupo, itens, total_grupo in grupos:
        linhas.append([grupo, "", "", num(total_grupo), ""])
        estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        i += 1
        for item, unidade, qtd, valor, unitario in itens:
            if item == grupo:  # grupo sem abertura por item: a linha do grupo já disse tudo
                continue
            linhas.append([Paragraph("   " + item, ST_CEL), unidade,
                           num(qtd), num(valor), num(unitario, 2)])
            i += 1
    linhas.append(["(-) Provisão para obsolescência de estoques", "", "", num(provisao), ""])
    i += 1
    linhas.append(["TOTAL DOS ESTOQUES", "", "", num(total), ""])
    estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black)])
    el.append(_tab(linhas, [104 * mm, 24 * mm, 30 * mm, 32 * mm, 32 * mm], estilos, fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — As colunas <b>Quantidade</b> e <b>Custo unitário</b> não estão em R$ mil: a "
        "primeira é quantidade física (t, milheiro, unidade) e a segunda é valor unitário em "
        "reais. Só a coluna <b>Valor</b> compõe o saldo do balanço.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# --------------------------------------------------------- SITUAÇÃO FISCAL ---
def pdf_situacao_fiscal(bp, ano, arquivo):
    parcelamentos, correntes, provisoes, tot_parc, tot_corr = X.situacao_fiscal(bp, ano)
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "SITUAÇÃO FISCAL E PARCELAMENTOS TRIBUTÁRIOS",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")

    el.append(Paragraph("1. Parcelamentos e transações tributárias", ST_H2))
    linhas = [["Empresa / Programa", "Tributos", "Parcelas", "Curto prazo", "Longo prazo", "Situação"]]
    for p in parcelamentos:
        linhas.append([
            Paragraph(f"<b>{p['entidade']}</b><br/>{p['programa']}", ST_CEL),
            Paragraph(p["tributos"], ST_CEL),
            f"{p['parcelas_pagas']}/{p['parcelas_total']}",
            num(p["saldo_cp"], dash_zero=True), num(p["saldo_lp"], dash_zero=True),
            Paragraph(p["situacao"], ST_CEL),
        ])
    linhas.append(["TOTAL DOS PARCELAMENTOS", "", "",
                   num(sum(p["saldo_cp"] for p in parcelamentos)),
                   num(sum(p["saldo_lp"] for p in parcelamentos)), ""])
    el.append(_tab(linhas, [58 * mm, 36 * mm, 16 * mm, 22 * mm, 22 * mm, 28 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)],
                   fonte=6.8))

    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph("2. Tributos correntes a recolher (Canastra Indústria)", ST_H2))
    linhas2 = [["Tributo", "Saldo"]]
    for rot, v in correntes:
        linhas2.append([rot, num(v)])
    linhas2.append(["TOTAL DOS TRIBUTOS CORRENTES", num(tot_corr)])
    el.append(_tab(linhas2, [120 * mm, 30 * mm],
                   [("FONTNAME", (0, len(linhas2) - 1), (-1, len(linhas2) - 1), "Helvetica-Bold")],
                   fonte=7.4))

    if provisoes:
        el.append(Spacer(1, 4 * mm))
        el.append(Paragraph("3. Provisões de natureza tributária", ST_H2))
        linhas3 = [["Provisão", "Saldo"]] + [[r, num(v)] for r, v in provisoes]
        el.append(_tab(linhas3, [120 * mm, 30 * mm], fonte=7.4))

    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        "Nota — Os saldos de <b>parcelamento</b> seguem cronograma contratado de amortização e "
        "extinguem-se ao fim do prazo. Os <b>tributos correntes a recolher</b> são de natureza "
        "rotativa: o saldo de um mês é liquidado no mês seguinte e substituído pela apuração "
        "seguinte, mantendo-se enquanto houver operação. As <b>provisões</b> dependem de decisão "
        "judicial ou acordo, sem data determinável.", ST_NOTA))
    el.append(Paragraph(
        "Nota — A adesão à transação tributária federal em 14/04/2025 implicou o reconhecimento "
        "de multas e juros no resultado do exercício, apresentados no resultado financeiro.",
        ST_NOTA))
    _assina(el, contador="Escritório Andrade & Peixoto — Assessoria Tributária", diretor=None)
    build(d, el)
    return arquivo


# ---------------------------------------------------------- CONTINGÊNCIAS ---
def pdf_contingencias(bp, ano, arquivo):
    linhas_c, provisionado, possivel, remoto = X.contingencias(bp, ano)
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "PROCESSOS JUDICIAIS E CONTINGÊNCIAS",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Natureza", "Objeto", "Prognóstico", "Valor em discussão", "Provisionado"]]
    estilos = []
    for i, (nat, desc, prog, valor, prov) in enumerate(linhas_c, start=1):
        linhas.append([nat, Paragraph(desc, ST_CEL), prog, num(valor, dash_zero=True),
                       num(prov, dash_zero=True)])
        if prog == "Provável":
            estilos.append(("TEXTCOLOR", (2, i), (2, i), colors.Color(.55, 0, 0)))
    linhas.append(["TOTAL", "", "", num(provisionado + possivel + remoto), num(provisionado)])
    estilos.extend([("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)])
    el.append(_tab(linhas, [24 * mm, 74 * mm, 22 * mm, 28 * mm, 24 * mm], estilos, fonte=6.9))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        f"Nota — Somente as causas com prognóstico <b>provável</b> estão provisionadas no passivo "
        f"({num(provisionado)}). As causas de perda <b>possível</b> ({num(possivel)}) e "
        f"<b>remota</b> ({num(remoto)}) são apenas divulgadas e <b>não integram o passivo</b> — a "
        "coluna TOTAL soma o valor em discussão, não a obrigação registrada.", ST_NOTA))
    _assina(el, contador="Menezes & Tavares Advogados Associados — OAB/MG 4.882", diretor=None)
    build(d, el)
    return arquivo


# ------------------------------------------------------------ IMOBILIZADO ---
def pdf_imobilizado(bp, ano, arquivo):
    linhas_i, custo, dep, liquido = X.imobilizado(bp, ano)
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "COMPOSIÇÃO DO ATIVO IMOBILIZADO",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Classe do bem", "Custo", "Taxa anual", "Depreciação acumulada", "Valor líquido"]]
    for rot, c, taxa, d_, liq in linhas_i:
        linhas.append([Paragraph(rot, ST_CEL), num(c),
                       pct(taxa) if taxa else "-", num(-d_, dash_zero=True), num(liq)])
    linhas.append(["TOTAL", num(custo), "", num(-dep), num(liquido)])
    el.append(_tab(linhas, [72 * mm, 26 * mm, 22 * mm, 34 * mm, 28 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)],
                   fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — A coluna <b>Taxa anual</b> é o percentual de depreciação aplicado a cada classe "
        "(vida útil estimada de 25 anos para edificações, 10 anos para máquinas e instalações e "
        "5 anos para veículos). Terrenos e imobilizado em andamento não são depreciados.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------------------ FOLHA ---
def pdf_folha(ano, arquivo):
    linhas_f, headcount, custo_anual = X.folha(ano)
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "RESUMO DA FOLHA DE PAGAMENTO",
                   f"Competência de dezembro de {ano} e projeção anual",
                   "Custo em R$ mil; salário médio em R$ mil; efetivo em número de pessoas")
    linhas = [["Área", "Efetivo (pessoas)", "Salário médio (R$ mil)",
               "Custo mensal (R$ mil)", "Custo anual com encargos (R$ mil)"]]
    for area, hc, medio, mensal, anual in linhas_f:
        linhas.append([area, str(hc), num(medio, 2), num(mensal, 1), num(anual, 1)])
    linhas.append(["TOTAL", str(headcount), "", "", num(custo_anual, 1)])
    el.append(_tab(linhas, [56 * mm, 26 * mm, 30 * mm, 30 * mm, 40 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)],
                   fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        f"Nota — A coluna <b>Efetivo</b> é a quantidade de empregados ({headcount} pessoas em "
        f"31/12/{ano}) e não um valor monetário. O custo anual considera 13º salário, férias e "
        "encargos (fator 13,33).", ST_NOTA))
    _assina(el, contador="Departamento Pessoal — Canastra Indústria", diretor=None)
    build(d, el)
    return arquivo


# --------------------------------------------------------------- EXTRATOS ---
def pdf_extratos(bp, ano, arquivo):
    linhas_e, total = X.extratos(bp, ano)
    d = doc(arquivo, marca=True)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "POSIÇÃO CONSOLIDADA DE SALDOS BANCÁRIOS",
                   f"Posição em 31 de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Instituição", "Agência", "Conta", "Tipo", "Saldo"]]
    for banco, ag, cc, tipo, v in linhas_e:
        linhas.append([Paragraph(banco, ST_CEL), ag, cc, tipo, num(v)])
    linhas.append(["TOTAL DO DISPONÍVEL", "", "", "", num(total)])
    el.append(_tab(linhas, [58 * mm, 20 * mm, 24 * mm, 44 * mm, 26 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black)],
                   fonte=7.2))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — O total corresponde ao subgrupo <b>Disponível</b> do ativo circulante. As contas "
        "vinculadas a operações de FINAME têm movimentação restrita.", ST_NOTA))
    _assina(el, contador="Ricardo N. Peixoto — Controller", diretor=None)
    build(d, el)
    return arquivo


# -------------------------------------------------------------- BALANCETE ---
def pdf_balancete(bp, ano, arquivo, ent="industria"):
    linhas_b = X.balancete(bp, ano, ent)
    e = D.ENTIDADES[ent]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "BALANCETE ANALÍTICO DE VERIFICAÇÃO",
                   f"Encerramento do exercício de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Código", "Conta", "Saldo", "D/C"]]
    for cod, rot, v, nat in linhas_b:
        linhas.append([cod, Paragraph(rot, ST_CEL), num(v), nat])
    deb = sum(v for _, _, v, n in linhas_b if n == "D")
    cre = sum(v for _, _, v, n in linhas_b if n == "C")
    linhas.append(["", "TOTAIS", f"D {num(deb)} / C {num(cre)}", ""])
    el.append(_tab(linhas, [26 * mm, 106 * mm, 32 * mm, 12 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("ALIGN", (3, 0), (3, -1), "CENTER")], fonte=6.8))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota — Os saldos são apresentados em <b>módulo</b>; o sinal é dado pela coluna "
        "<b>D/C</b> (devedor ou credor). Conta redutora do ativo tem natureza credora, e conta "
        "redutora do passivo, devedora.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------------------ RAZÃO ---
def pdf_razao(bp, ano, arquivo):
    linhas_r, abertura, debitos, creditos, saldo_final = X.razao_fornecedores(bp, ano)
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "LIVRO RAZÃO — CONTA 2.1.01.001 FORNECEDORES NACIONAIS",
                   f"Movimento de dezembro de {ano}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    linhas = [["Data", "Lançamento", "Histórico", "Débito", "Crédito", "Saldo", "D/C"]]
    linhas.append([f"01/12/{ano}", "", "SALDO ANTERIOR", "", "", num(abertura), "C"])
    for data, lc, hist, deb, cred, saldo, nat in linhas_r:
        linhas.append([data, lc, Paragraph(hist, ST_CEL), num(deb, dash_zero=True),
                       num(cred, dash_zero=True), num(saldo), nat])
    linhas.append(["", "", "TOTAIS DO PERÍODO", num(debitos), num(creditos), num(saldo_final), "C"])
    el.append(_tab(linhas, [17 * mm, 22 * mm, 76 * mm, 20 * mm, 20 * mm, 22 * mm, 8 * mm],
                   [("FONTNAME", (0, len(linhas) - 1), (-1, len(linhas) - 1), "Helvetica-Bold"),
                    ("LINEABOVE", (0, len(linhas) - 1), (-1, len(linhas) - 1), 0.5, colors.black),
                    ("ALIGN", (6, 0), (6, -1), "CENTER")], fonte=6.2))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------- DOCUMENTOS TEXTO ---
def pdf_certidoes(arquivo):
    """Documento SEM nenhum valor financeiro. Um extrator que produzir linha
    monetária aqui está inventando dado."""
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "RELAÇÃO DE CERTIDÕES E REGULARIDADE FISCAL",
                   "Consultas realizadas em 12 de janeiro de 2026", None)
    linhas = [["Empresa", "Certidão", "Órgão", "Situação", "Validade"]]
    dados = [
        ("Canastra Indústria de Embalagens Ltda.", "CND Federal (RFB/PGFN)", "Receita Federal",
         "Positiva com efeito de negativa", "11/07/2026"),
        ("Canastra Indústria de Embalagens Ltda.", "CRF - FGTS", "Caixa Econômica Federal",
         "Regular", "20/02/2026"),
        ("Canastra Indústria de Embalagens Ltda.", "CNDT - Débitos Trabalhistas", "TST",
         "Positiva", "-"),
        ("Canastra Indústria de Embalagens Ltda.", "Certidão Estadual de ICMS", "SEFAZ/MG",
         "Positiva com efeito de negativa", "08/04/2026"),
        ("Canastra Comercial e Distribuidora Ltda.", "CND Federal (RFB/PGFN)", "Receita Federal",
         "Positiva", "-"),
        ("Canastra Comercial e Distribuidora Ltda.", "Certidão Estadual de ICMS", "SEFAZ/MG",
         "Positiva", "-"),
        ("CN Transportes e Logística Ltda.", "CND Federal (RFB/PGFN)", "Receita Federal",
         "Negativa", "03/06/2026"),
        ("Canastra Agroflorestal Ltda.", "CND Federal (RFB/PGFN)", "Receita Federal",
         "Negativa", "27/05/2026"),
        ("Canastra Imobiliária SPE Ltda.", "Certidão de Débitos Municipais", "Prefeitura",
         "Negativa", "14/03/2026"),
    ]
    for row in dados:
        linhas.append([Paragraph(row[0], ST_CEL), Paragraph(row[1], ST_CEL),
                       Paragraph(row[2], ST_CEL), Paragraph(row[3], ST_CEL), row[4]])
    el.append(_tab(linhas, [50 * mm, 40 * mm, 32 * mm, 40 * mm, 20 * mm], fonte=6.9))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        "Certidão <b>positiva com efeito de negativa</b> indica débitos com exigibilidade "
        "suspensa por parcelamento em dia ou discussão judicial com garantia. Certidão "
        "<b>positiva</b> sem ressalva indica débitos exigíveis, o que impede a contratação com "
        "o poder público e a obtenção de financiamentos oficiais.", ST_TXT))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Este documento não contém valores monetários: ele registra a situação cadastral das "
        "empresas perante os órgãos indicados.", ST_NOTA))
    build(d, el)
    return arquivo


def pdf_contrato_social(bp, tot, arquivo):
    capital = 0
    for sub in bp[2025]["industria"]["PL"].values():
        for rot, v in sub:
            if rot.startswith("Capital social"):
                capital = v
    d = doc(arquivo)
    el = cabecalho(D.ENTIDADES["industria"]["razao_social"], D.ENTIDADES["industria"]["cnpj"],
                   "CONTRATO SOCIAL CONSOLIDADO — 7ª ALTERAÇÃO",
                   "Arquivado na JUCEMG sob o nº 31.2024.887.114 em 19/09/2024", None)
    for titulo, texto in [
        ("CLÁUSULA PRIMEIRA — DENOMINAÇÃO E SEDE",
         "A sociedade gira sob a denominação de CANASTRA INDÚSTRIA DE EMBALAGENS LTDA., com sede "
         "na Rodovia MG-050, km 118, Distrito Industrial, no município de São Roque de Minas, "
         "Estado de Minas Gerais, inscrita no CNPJ sob o nº 44.555.667/0001-59."),
        ("CLÁUSULA SEGUNDA — OBJETO SOCIAL",
         "A sociedade tem por objeto a fabricação de embalagens de papelão ondulado, chapas e "
         "acessórios, a prestação de serviços de conversão e corte, e a participação em outras "
         "sociedades como sócia ou acionista."),
        ("CLÁUSULA TERCEIRA — CAPITAL SOCIAL",
         f"O capital social é de R$ {num(capital)} mil (R$ {num(capital * 1000)}), dividido em "
         f"{num(capital)} mil quotas no valor nominal de R$ 1.000,00 cada uma, totalmente "
         "subscrito e integralizado em moeda corrente nacional, assim distribuído: CANASTRA "
         "PARTICIPAÇÕES S.A., detentora de 100% das quotas."),
        ("CLÁUSULA QUARTA — ADMINISTRAÇÃO",
         "A administração da sociedade compete ao sócio administrador Paulo Sérgio Canastra, "
         "brasileiro, casado, engenheiro, CPF 987.654.321-00, a quem cabe a representação ativa "
         "e passiva, judicial e extrajudicial."),
        ("CLÁUSULA QUINTA — EXERCÍCIO SOCIAL",
         "O exercício social coincide com o ano civil, encerrando-se em 31 de dezembro de cada "
         "ano, quando serão levantadas as demonstrações contábeis exigidas em lei."),
        ("CLÁUSULA SEXTA — RESPONSABILIDADE",
         "A responsabilidade dos sócios é restrita ao valor de suas quotas, mas todos respondem "
         "solidariamente pela integralização do capital social."),
    ]:
        el.append(Paragraph(titulo, ST_H2))
        el.append(Paragraph(texto, ST_TXT))
        el.append(Spacer(1, 2 * mm))
    el.append(Spacer(1, 5 * mm))
    el.append(Paragraph("São Roque de Minas (MG), 19 de setembro de 2024.", ST_TXT))
    _assina(el, contador="Paulo Sérgio Canastra — Sócio Administrador",
            diretor="Visto: Menezes & Tavares Advogados Associados — OAB/MG 4.882")
    build(d, el)
    return arquivo


def pdf_organograma(arquivo):
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "ORGANOGRAMA SOCIETÁRIO",
                   "Posição em 31 de dezembro de 2025", None)
    linhas = [["Controladora", "Controlada", "Participação", "País", "Atividade"]]
    for k in D.CONTROLADAS:
        linhas.append([
            Paragraph(D.ENTIDADES["holding"]["razao_social"], ST_CEL),
            Paragraph(D.ENTIDADES[k]["razao_social"], ST_CEL),
            pct(D.PARTICIPACAO[k] * 100, 0), "Brasil",
            {"industria": "Fabricação de embalagens de papelão ondulado",
             "comercial": "Comércio atacadista de embalagens",
             "transportes": "Transporte rodoviário de cargas",
             "agro": "Silvicultura e produção de madeira",
             "imob": "Locação de imóveis próprios"}[k],
        ])
    el.append(_tab(linhas, [46 * mm, 52 * mm, 22 * mm, 16 * mm, 46 * mm], fonte=6.9))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        "Os 35% restantes do capital da CN Transportes e Logística Ltda. pertencem a sócio "
        "pessoa física sem vínculo com o grupo controlador. O quadro societário da CANASTRA "
        "PARTICIPAÇÕES S.A. é composto por três pessoas físicas da mesma família.", ST_TXT))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "As participações estão expressas em percentual do capital votante e total; este "
        "documento não contém valores monetários.", ST_NOTA))
    build(d, el)
    return arquivo


def pdf_notas(bp, tot, arquivo):
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "NOTAS EXPLICATIVAS ÀS DEMONSTRAÇÕES CONTÁBEIS",
                   "Exercício encerrado em 31 de dezembro de 2025",
                   "(Valores expressos em milhares de reais — R$ mil, salvo indicação em contrário)")
    t25 = tot[2025]["industria"]
    t24 = tot[2024]["industria"]
    ccl = t25["AC"] - t25["PC"]
    divida = X.divida_bancaria(bp, 2025)
    for titulo, texto in [
        ("1. CONTEXTO OPERACIONAL E CONTINUIDADE",
         "A Canastra Indústria de Embalagens Ltda. e suas partes relacionadas atuam na fabricação "
         "e distribuição de embalagens de papelão ondulado. No exercício encerrado em 31 de "
         "dezembro de 2025 a Sociedade apurou prejuízo e apresenta capital circulante líquido "
         f"negativo de R$ {num(abs(ccl))} mil e patrimônio líquido de R$ {num(t25['PL'])} mil "
         f"(R$ {num(t24['PL'])} mil em 2024). A continuidade das operações depende da conclusão "
         "da renegociação do endividamento bancário, do cumprimento do cronograma da transação "
         "tributária federal e do suporte financeiro da controladora, que manifestou formalmente "
         "sua intenção de manter o apoio pelos próximos doze meses. Estas demonstrações foram "
         "preparadas no pressuposto de continuidade e não contemplam ajustes que seriam "
         "necessários caso esse pressuposto não se confirme."),
        ("2. DESCUMPRIMENTO DE CLÁUSULA RESTRITIVA (COVENANT)",
         "Os contratos de capital de giro mantidos com o Banco Meridional S.A. preveem índice "
         "mínimo de cobertura de juros (EBITDA sobre despesa financeira) de 1,5x, apurado "
         "anualmente. O índice apurado em 31/12/2025 não atingiu o mínimo contratado. Em "
         "decorrência, e conforme requerido pelo CPC 26, os saldos originalmente classificados no "
         "passivo não circulante foram integralmente reclassificados para o passivo circulante, "
         "ainda que o credor não tenha, até a data de aprovação destas demonstrações, exercido a "
         "faculdade de vencimento antecipado."),
        ("3. ENDIVIDAMENTO",
         f"O endividamento bancário totaliza R$ {num(divida)} mil em 31/12/2025, dos quais a "
         "maior parcela vence em até doze meses em razão da reclassificação descrita na Nota 2. "
         "Uma tranche está denominada em dólar dos Estados Unidos (pré-pagamento de exportação), "
         "convertida pela taxa de fechamento do exercício. As garantias compreendem aval dos "
         "sócios, alienação fiduciária de máquinas e cessão fiduciária de duplicatas."),
        ("4. TRANSAÇÃO TRIBUTÁRIA",
         "Em 14 de abril de 2025 a Sociedade aderiu à transação tributária federal, incluindo "
         "débitos de IRPJ, CSLL, PIS, COFINS e contribuições previdenciárias, em 60 parcelas "
         "mensais. O saldo está segregado entre passivo circulante e não circulante conforme o "
         "cronograma contratado. Os encargos de multa e juros reconhecidos na adesão foram "
         "registrados no resultado financeiro do exercício."),
        ("5. PARTES RELACIONADAS",
         "As operações com partes relacionadas compreendem mútuos com a controladora, "
         "fornecimento de matéria-prima pela Canastra Agroflorestal Ltda., locação de galpões da "
         "Canastra Imobiliária SPE Ltda. e serviços de transporte prestados pela CN Transportes e "
         "Logística Ltda. Os mútuos são remunerados a 100% do CDI e não têm vencimento "
         "contratado."),
        ("6. INSTRUMENTOS FINANCEIROS E RISCOS",
         "A Sociedade está exposta a risco de liquidez, risco de taxa de juros (dívida indexada "
         "ao CDI) e risco cambial (tranche em dólar e vendas ao mercado externo). Não são "
         "utilizados instrumentos financeiros derivativos para proteção."),
        ("7. EVENTOS SUBSEQUENTES",
         "Em 22 de janeiro de 2026 a Sociedade protocolou pedido de mediação pré-processual com "
         "os principais credores financeiros, com vistas à repactuação de prazos e encargos. "
         "Até a data de aprovação destas demonstrações não havia decisão sobre o pedido."),
    ]:
        el.append(Paragraph(titulo, ST_H2))
        el.append(Paragraph(texto, ST_TXT))
        el.append(Spacer(1, 2 * mm))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Este documento é texto corrido e não constitui demonstração financeira em si — os "
        "valores citados são referências às demonstrações que o acompanham.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


def pdf_parecer(arquivo):
    d = doc(arquivo)
    el = cabecalho("CAMPOS, RIBEIRO & ASSOCIADOS AUDITORES INDEPENDENTES", "18.994.221/0001-05",
                   "RELATÓRIO DO AUDITOR INDEPENDENTE SOBRE AS DEMONSTRAÇÕES CONTÁBEIS",
                   "Exercício encerrado em 31 de dezembro de 2025", None)
    for titulo, texto in [
        ("OPINIÃO COM RESSALVA",
         "Examinamos as demonstrações contábeis da CANASTRA INDÚSTRIA DE EMBALAGENS LTDA., que "
         "compreendem o balanço patrimonial em 31 de dezembro de 2025 e as respectivas "
         "demonstrações do resultado, das mutações do patrimônio líquido e dos fluxos de caixa "
         "para o exercício findo nessa data. Em nossa opinião, exceto pelos efeitos do assunto "
         "descrito na seção a seguir, as demonstrações contábeis apresentam adequadamente, em "
         "todos os aspectos relevantes, a posição patrimonial e financeira da Sociedade."),
        ("BASE PARA OPINIÃO COM RESSALVA",
         "A Sociedade mantém registrado no ativo não circulante tributo diferido ativo constituído "
         "sobre prejuízos fiscais, cuja realização depende da geração de lucros tributáveis "
         "futuros. Não nos foi disponibilizado estudo técnico de viabilidade que suporte a "
         "expectativa de realização no prazo previsto na legislação, razão pela qual não foi "
         "possível concluir sobre a adequação do saldo registrado."),
        ("INCERTEZA RELEVANTE RELACIONADA COM A CONTINUIDADE OPERACIONAL",
         "Chamamos a atenção para a Nota Explicativa 1, que descreve prejuízo no exercício, "
         "capital circulante líquido negativo e descumprimento de cláusula restritiva contratual. "
         "Esses eventos indicam a existência de incerteza relevante que pode levantar dúvida "
         "significativa quanto à capacidade de continuidade operacional da Sociedade. Nossa "
         "opinião não contém modificação relacionada a esse assunto."),
        ("OUTROS ASSUNTOS",
         "As demonstrações contábeis do exercício findo em 31 de dezembro de 2024, apresentadas "
         "para fins de comparação, foram por nós examinadas e sobre elas emitimos relatório em 28 "
         "de março de 2025, com ressalva de mesma natureza."),
    ]:
        el.append(Paragraph(titulo, ST_H2))
        el.append(Paragraph(texto, ST_TXT))
        el.append(Spacer(1, 2 * mm))
    el.append(Spacer(1, 5 * mm))
    el.append(Paragraph("Belo Horizonte (MG), 27 de março de 2026.", ST_TXT))
    _assina(el, contador="Campos, Ribeiro & Associados — CRC 2MG-004.117/O-9",
            diretor="Luiz Otávio Campos — Contador — CRC 1MG-071.338/O-4")
    build(d, el)
    return arquivo


# ------------------------------------------- DEMONSTRAÇÕES COMPLETAS (PDF ÚNICO)
def pdf_df_completa(bp, tot, ano, arquivo):
    """O arquivo COMPOSTO: balanço, DRE, fluxo de caixa e notas num PDF só.

    É o formato em que o conjunto chega num mandato real ("Demonstrações
    Contábeis 2024.pdf") e o que obriga o roteamento por linha — um documento,
    quatro demonstrações, quatro abas."""
    ant = D.ANOS[D.ANOS.index(ano) - 1]
    e = D.ENTIDADES["industria"]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÕES CONTÁBEIS",
                   f"Exercícios encerrados em 31 de dezembro de {ano} e de {ant}",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(Paragraph("BALANÇO PATRIMONIAL", ST_H2))
    el.append(tabela_balanco(bp, tot, "industria", [ano, ant]))
    el.append(PageBreak())

    el.append(Paragraph("DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO", ST_H2))
    dre = X.dre_industria(bp, tot)
    linhas, estilos = [[""] + [str(a) for a in (ano, ant)]], []
    i = 1
    for rot, _v, tipo in dre[ano]:
        valores = [next((v for r, v, t in dre[a] if r == rot), None) for a in (ano, ant)]
        linhas.append([rot] + [num(v) for v in valores])
        if tipo in ("ancora", "subtotal"):
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        i += 1
    el.append(_tab(linhas, [104 * mm, 34 * mm, 34 * mm], estilos, fonte=7.0))
    el.append(PageBreak())

    el.append(Paragraph("DEMONSTRAÇÃO DOS FLUXOS DE CAIXA — MÉTODO INDIRETO", ST_H2))
    linhas_dfc, ini, fim = X.dfc(bp, tot, ano)
    linhas, estilos = [["", str(ano)]], []
    i = 1
    for rot, v, tipo in linhas_dfc:
        linhas.append([rot, num(v)])
        if tipo in ("ancora", "subtotal"):
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        i += 1
    el.append(_tab(linhas, [130 * mm, 32 * mm], estilos, fonte=7.2))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph("NOTAS EXPLICATIVAS — RESUMO", ST_H2))
    el.append(Paragraph(
        "1. A Sociedade opera na fabricação de embalagens de papelão ondulado. 2. As "
        "demonstrações foram elaboradas de acordo com as práticas contábeis adotadas no Brasil "
        "(NBC TG 1000). 3. O estoque é avaliado ao custo médio ponderado, ajustado ao valor "
        "líquido de realização. 4. O imobilizado é depreciado pelo método linear às taxas que "
        "contemplam a vida útil estimada dos bens. 5. Perdas estimadas em créditos de liquidação "
        "duvidosa são constituídas com base na análise individual dos sacados vencidos há mais de "
        "180 dias.", ST_TXT))
    _assina(el)
    build(d, el)
    return arquivo
