# -*- coding: utf-8 -*-
"""Renderização do book PIRAQUARA em PDF.

Mesmo desenho do `book-canastra/render.py` (cabeçalho, rodapé sintético, tabela
com negativo entre parênteses, assinatura), com uma diferença que o canastra NÃO
tem: `rl_config.invariant = 1`. Sem isso o reportlab grava a hora da geração em
`/CreationDate` e `/ModDate` e deriva o `/ID` dela, e o mesmo gerador produz
bytes diferentes a cada execução — o canastra, medido em 22/09/2026, muda o md5
de todos os PDFs de uma rodada para a outra. Aqui a data do metadado é fixa e
dois `gerar.py` seguidos dão os MESMOS bytes (conferido no README).

A contagem de verdade das linhas de conta (o denominador da régua de cobertura)
vem de `Dados de Teste/comum/contagem.py`, a mesma dos outros dois books.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from reportlab import rl_config

rl_config.invariant = 1  # data de metadado fixa e /ID determinístico — ver docstring

from reportlab.lib import colors  # noqa: E402
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY  # noqa: E402
from reportlab.lib.pagesizes import A4, landscape  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402
from reportlab.lib.units import mm  # noqa: E402
from reportlab.platypus import (PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table,  # noqa: E402
                                TableStyle)

import dados as D  # noqa: E402
import demonstracoes as X  # noqa: E402
from comum.contagem import CONTAGEM, SEM_VALOR_MONETARIO, build  # noqa: E402,F401

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdf")
os.makedirs(OUT, exist_ok=True)

RODAPE_SINTETICO = ("Documento sintético, gerado para teste de sistema. Não corresponde a "
                    "empresa, pessoa ou fato real.")
CONTADOR = "Marta L. Quintela — Contadora — CRC 1PR-077.915/O-2"
DIRETOR = "Otávio R. Piraquara — Diretor Presidente — CPF 123.456.789-09"
CONTROLLER = "Henrique B. Sallum — Controller"

ST_TIT = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=11, alignment=TA_CENTER, leading=14)
ST_SUB = ParagraphStyle("s", fontName="Helvetica", fontSize=8.5, alignment=TA_CENTER, leading=11)
ST_NOTA = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=7, leading=9)
ST_TXT = ParagraphStyle("p", fontName="Helvetica", fontSize=8.5, leading=12, alignment=TA_JUSTIFY)
ST_H2 = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=9, leading=13, spaceBefore=6)
ST_CEL = ParagraphStyle("c", fontName="Helvetica", fontSize=6.6, leading=8)

MIL = "(Valores expressos em milhares de reais — R$ mil)"


# --------------------------------------------------------------- FORMATAÇÃO --
def num(v, casas=0, dash_zero=False):
    """Número como o documento imprime: ponto de milhar, vírgula decimal,
    negativo entre parênteses. None = célula vazia (conta que não existia)."""
    if v is None:
        return ""
    if v == 0 and dash_zero:
        return "-"
    s = f"{abs(v):,.{casas}f}".replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    return f"({s})" if v < 0 else s


def reais(centavos):
    return num(centavos / 100, 2)


def pct(v, casas=1):
    return f"{v:.{casas}f}".replace(".", ",") + "%"


def vezes(v):
    return "n/a" if v is None else f"{v:.2f}".replace(".", ",") + "x"


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


def _rodape(canvas, doc_):
    canvas.saveState()
    canvas.setFont("Helvetica", 6.5)
    canvas.setFillColorRGB(.35, .35, .35)
    canvas.drawRightString(doc_.pagesize[0] - 15 * mm, 8 * mm, f"Página {canvas.getPageNumber()}")
    canvas.drawString(15 * mm, 8 * mm, RODAPE_SINTETICO)
    canvas.restoreState()


def doc(nome_arquivo, paisagem=False):
    d = SimpleDocTemplate(
        os.path.join(OUT, nome_arquivo),
        pagesize=landscape(A4) if paisagem else A4,
        leftMargin=14 * mm, rightMargin=14 * mm, topMargin=13 * mm, bottomMargin=15 * mm,
        title=nome_arquivo.replace(".pdf", ""), author="Sistema sintético de teste",
    )
    d._decorador = _rodape
    return d


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


def _negrito(i, fundo=False, linha=True):
    e = [("FONTNAME", (0, i), (-1, i), "Helvetica-Bold")]
    if linha:
        e.append(("LINEABOVE", (0, i), (-1, i), 0.4, colors.black))
    if fundo:
        e.append(("BACKGROUND", (0, i), (-1, i), colors.Color(.92, .92, .92)))
    return e


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


def _periodo(anos):
    datas = [f"31 de dezembro de {a}" for a in anos]
    return "Exercícios encerrados em " + ", ".join(datas[:-1]) + " e em " + datas[-1]


# ------------------------------------------------------------------ BALANÇO --
def _uniao(listas):
    out = []
    for lst in listas:
        for x in lst:
            if x not in out:
                out.append(x)
    return out


def tabela_balanco(bp, tot, ent, anos):
    """Uma coluna por exercício. Conta que não existe num exercício: célula
    VAZIA, não zero (o não circulante de empréstimos em 2025, a reclassificação
    antes de 2025, o impairment, o parcelamento, a provisão para passivo a
    descoberto, o mútuo antes do contrato)."""
    n = len(anos)
    linhas = [[""] + [f"31/12/{a}" for a in anos]]
    estilos = []

    def add(rot, valores, estilo=None, indent=0):
        i = len(linhas)
        linhas.append(["  " * indent + rot] + [num(v) for v in valores])
        if estilo == "grupo":
            estilos.extend(_negrito(i, fundo=True))
        elif estilo == "secao":
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
        elif estilo == "sub":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Oblique"),
                            ("TEXTCOLOR", (0, i), (-1, i), colors.Color(.25, .25, .25))])
        elif estilo == "total":
            estilos.extend(_negrito(i))

    # A ORDEM é a do plano de contas, não a do exercício mais recente: conta que
    # deixou de existir em 2025 (o não circulante de empréstimos) continua no
    # lugar dela, com a célula de 2025 vazia.
    plano = D.PLANOS[ent]()

    def ordem_do_plano(sec, sub, rotulos):
        contas = plano[sec].get(sub)
        pos = [r for r, _v in contas] if isinstance(contas, list) else []
        return sorted(rotulos, key=lambda r: pos.index(r) if r in pos else len(pos))

    def secao(sec, label, total_por_ano):
        add(label, total_por_ano, "secao")
        existentes = _uniao([list(bp[a][ent][sec]) for a in anos])
        for sub in [x for x in plano[sec] if x in existentes]:
            por_ano = {a: dict(bp[a][ent][sec].get(sub, [])) for a in anos}
            add(sub, [sum(por_ano[a].values()) if por_ano[a] else None for a in anos], "sub", 1)
            for r in ordem_do_plano(sec, sub, _uniao([list(por_ano[a]) for a in anos])):
                add(r, [por_ano[a].get(r) for a in anos], None, 2)

    add("ATIVO", [tot[a][ent]["ATIVO"] for a in anos], "grupo")
    secao("AC", "Ativo Circulante", [tot[a][ent]["AC"] for a in anos])
    if any(bp[a][ent]["ANC"] for a in anos):
        secao("ANC", "Ativo Não Circulante", [tot[a][ent]["ANC"] for a in anos])
    add("TOTAL DO ATIVO", [tot[a][ent]["ATIVO"] for a in anos], "total")
    linhas.append([""] * (n + 1))
    add("PASSIVO E PATRIMÔNIO LÍQUIDO", [tot[a][ent]["PASSIVO_PL"] for a in anos], "grupo")
    secao("PC", "Passivo Circulante", [tot[a][ent]["PC"] for a in anos])
    if any(bp[a][ent]["PNC"] for a in anos):
        secao("PNC", "Passivo Não Circulante",
              [tot[a][ent]["PNC"] if bp[a][ent]["PNC"] else None for a in anos])
    # O rótulo do PL já avisa quando ele é negativo — é o que o documento real faz.
    rot_pl = ("Patrimônio Líquido (Passivo a Descoberto)"
              if any(tot[a][ent]["PL"] < 0 for a in anos) else "Patrimônio Líquido")
    secao("PL", rot_pl, [tot[a][ent]["PL"] for a in anos])
    add("TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", [tot[a][ent]["PASSIVO_PL"] for a in anos], "total")
    return _tab(linhas, [(182 - 26 * n) * mm] + [26 * mm] * n, estilos, fonte=7.0)


def pdf_balanco(bp, tot, ent, anos, arquivo, nota_extra=None):
    e = D.ENTIDADES[ent]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "BALANÇO PATRIMONIAL", _periodo(anos), MIL)
    el.append(tabela_balanco(bp, tot, ent, anos))
    el.append(Spacer(1, 4 * mm))
    for n in (nota_extra or []):
        el.append(Paragraph(n, ST_NOTA))
        el.append(Spacer(1, 1.5 * mm))
    el.append(Paragraph("As notas explicativas são parte integrante das demonstrações contábeis.",
                        ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------------- DRE ---
def pdf_dre(dre_ent, ent, anos, arquivo, notas=()):
    """Linhas na ordem do exercício mais recente; linha que só existe em outro
    exercício entra depois, e as células dos anos em que ela não existe ficam
    vazias (impairment só em 2025)."""
    e = D.ENTIDADES[ent]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO",
                   _periodo(anos), MIL)
    tipos = {}
    for a in anos:
        for r, _v, t in dre_ent[a]:
            tipos.setdefault(r, t)
    rotulos = _uniao([[r for r, _v, _t in dre_ent[a]] for a in anos])
    linhas, estilos = [[""] + [str(a) for a in anos]], []
    for rot in rotulos:
        i = len(linhas)
        valores = [next((v for r, v, _t in dre_ent[a] if r == rot), None) for a in anos]
        # Linha de resultado: o rótulo muda de LUCRO para PREJUÍZO conforme o ano,
        # então as duas viram uma linha só — mas com o sinal de cada exercício.
        linhas.append([rot] + [num(v, dash_zero=True) for v in valores])
        if tipos[rot] == "ancora":
            estilos.extend(_negrito(i, fundo=True))
        elif tipos[rot] == "subtotal":
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
    el.append(_tab(linhas, [100 * mm] + [27 * mm] * len(anos), estilos, fonte=7.1))
    el.append(Spacer(1, 4 * mm))
    for n in notas:
        el.append(Paragraph(n, ST_NOTA))
        el.append(Spacer(1, 1.5 * mm))
    _assina(el)
    build(d, el)
    return arquivo


def unifica_resultado(dre_ent):
    """A última linha de cada ano é LUCRO ou PREJUÍZO conforme o sinal. Para o
    comparativo, as duas viram "LUCRO (PREJUÍZO) DO EXERCÍCIO" — é como a DRE
    comparativa real imprime quando os anos têm sinais diferentes."""
    out = {}
    sinais = {a: dre_ent[a][-1][1] > 0 for a in dre_ent}
    for a, linhas in dre_ent.items():
        rot, v, t = linhas[-1]
        if len(set(sinais.values())) > 1:
            rot = "LUCRO (PREJUÍZO) LÍQUIDO DO EXERCÍCIO"
        out[a] = linhas[:-1] + [(rot, v, t)]
    return out


# --------------------------------------------------------------------- DFC ---
def pdf_dfc(bp, dre_met, anos, arquivo):
    e = D.ENTIDADES["metalurgica"]
    por_ano = {a: X.dfc_metalurgica(bp, dre_met, a)[0] for a in anos}
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DOS FLUXOS DE CAIXA — MÉTODO INDIRETO",
                   _periodo(anos), MIL)
    linhas, estilos = [[""] + [str(a) for a in anos]], []
    for k, (rot, _v, tipo) in enumerate(por_ano[anos[0]]):
        i = len(linhas)
        linhas.append([rot] + [num(por_ano[a][k][1], dash_zero=True) for a in anos])
        if tipo == "ancora":
            estilos.extend(_negrito(i, fundo=True))
        elif tipo == "subtotal":
            estilos.append(("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"))
    el.append(_tab(linhas, [120 * mm] + [30 * mm] * len(anos), estilos, fonte=7.1))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph(
        "Nota — Os juros sobre mútuos com partes relacionadas são capitalizados ao saldo devedor e "
        "não transitam pelo caixa; por isso são revertidos no fluxo operacional. Os juros sobre "
        "empréstimos bancários foram pagos no exercício e estão contidos no resultado.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------------ MAPA DE DÍVIDA -
def pdf_mapa_divida(bp, dre_met, ano, arquivo):
    e = D.ENTIDADES["metalurgica"]
    contratos = X.mapa_divida(ano)
    cov = X.covenant(bp, dre_met)
    ant = ano - 1
    d = doc(arquivo, paisagem=True)
    el = cabecalho(e["razao_social"], e["cnpj"], "MAPA DE ENDIVIDAMENTO BANCÁRIO E APURAÇÃO DE COVENANT",
                   f"Posição em 31 de dezembro de {ano}", MIL)
    cab = ["Credor", "Modalidade", "Contrato", "Taxa contratual", "Custo efetivo",
           "Garantia", "Covenant", f"Saldo 31/12/{ant}", f"Saldo 31/12/{ano}", f"Juros {ano}"]
    linhas, estilos = [cab], []
    for k in contratos:
        # Texto PURO nas células, não Paragraph: o Paragraph é desenhado num bloco
        # de texto à parte, e a leitura por coordenada (a do n8n) o separa da
        # linha — o credor sairia longe do próprio saldo.
        linhas.append([k["credor"], k["modalidade"],
                       k["contrato"], k["taxa"], pct(k["taxa_efetiva"] * 100, 2),
                       k["garantia"], "Sim" if k["covenant"] else "Não",
                       num(k["saldo_anterior"]), num(k["saldo"]), num(k["juros"])])
    tot_ant = sum(k["saldo_anterior"] or 0 for k in contratos)
    tot = sum(k["saldo"] for k in contratos)
    juros = sum(k["juros"] for k in contratos)
    assert tot == X.divida_bancaria(ano) and juros == X.juros_bancarios(ano)
    i = len(linhas)
    linhas.append(["TOTAL", "", "", "", "", "", "", num(tot_ant), num(tot), num(juros)])
    estilos.extend(_negrito(i))
    estilos.append(("ALIGN", (0, 0), (5, 0), "LEFT"))
    el.append(_tab(linhas, [42 * mm, 34 * mm, 22 * mm, 22 * mm, 15 * mm, 46 * mm, 13 * mm,
                            24 * mm, 24 * mm, 18 * mm], estilos, fonte=6.4))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        f"Nota 1 — Em razão do descumprimento do índice apurado abaixo, os credores dos contratos "
        f"marcados com covenant declararam o vencimento antecipado em 18/02/2026 (evento "
        f"subsequente). Todo o saldo foi classificado no passivo circulante em 31/12/{ano}: "
        f"R$ {num(X.saldos_emprestimos(ano)[0])} mil pelo cronograma original e "
        f"R$ {num(X.saldos_emprestimos(ano)[1])} mil reclassificados do não circulante. O contrato "
        f"FIN-2021-0457 tem cláusula de vencimento cruzado (cross-default) e também foi reclassificado.",
        ST_NOTA))
    # Página própria para a apuração. Não é estética: na mesma página, a leitura
    # por coordenada (`comum/extrai.linhas`, a forma do n8n) intercalou as linhas
    # das duas tabelas — medido na primeira geração deste book.
    el.append(PageBreak())

    # O CÁLCULO DO COVENANT, com cada parcela à vista. Três exercícios para que
    # a trajetória (folga → limite → rompimento) seja lida no próprio documento.
    anos = list(D.ANOS)
    el.append(Paragraph("APURAÇÃO DO ÍNDICE FINANCEIRO — DÍVIDA LÍQUIDA / EBITDA (cláusula 7.2)", ST_H2))
    cab2 = ["Item"] + [f"31/12/{a}" for a in anos]
    itens = [
        ("Dívida bancária bruta (quadro acima)", "divida_bruta"),
        ("(-) Disponível (saldo bancário)", "caixa"),
        ("(=) Dívida líquida", "divida_liquida"),
        ("Resultado operacional antes do resultado financeiro (DRE)", "ebit"),
        ("(+) Depreciação", "depreciacao"),
        ("(+) Perda por redução ao valor recuperável (impairment)", "impairment"),
        ("(=) EBITDA contratual", "ebitda"),
    ]
    l2, e2 = [cab2], []
    for rot, ch in itens:
        i = len(l2)
        vals = [-cov[a][ch] if ch == "caixa" else cov[a][ch] for a in anos]
        l2.append([rot] + [num(v, dash_zero=True) for v in vals])
        if rot.startswith("(=)"):
            e2.extend(_negrito(i))
    i = len(l2)
    l2.append(["Dívida líquida / EBITDA"] + [vezes(cov[a]["indice"]) for a in anos])
    e2.extend(_negrito(i, fundo=True))
    l2.append(["Limite contratual (máximo)"] + [vezes(D.COVENANT_LIMITE) for a in anos])
    i = len(l2)
    l2.append(["Situação"] + ["ROMPIDO" if cov[a]["rompido"] else "Cumprido" for a in anos])
    e2.extend(_negrito(i, linha=False))
    el.append(_tab(l2, [110 * mm] + [30 * mm] * len(anos), e2, fonte=7.2))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Nota 2 — Pela cláusula 7.3, a dívida líquida considera exclusivamente a dívida BANCÁRIA; os "
        "mútuos com partes relacionadas (documento próprio) não integram o índice. O EBITDA "
        "contratual soma ao resultado operacional a depreciação e o impairment, e NÃO exclui as "
        "provisões para perdas de crédito, de estoques e de contingências.", ST_NOTA))
    _assina(el, contador=CONTROLLER, diretor=None)
    build(d, el)
    return arquivo


# ------------------------------------------------------------------ MÚTUOS ---
def pdf_mutuos(bp, ano, arquivo):
    tm = X.mutuos_tabela()
    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.GRUPO, None, "RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS",
                   f"Movimentação do exercício de {ano}", MIL)
    cab = ["Contrato", "Mutuante (credora)", "Mutuária (devedora)", "Remuneração",
           f"Saldo 31/12/{ano - 1}", f"Captações {ano}", f"Juros capitalizados {ano}",
           f"Saldo 31/12/{ano}"]
    linhas, estilos = [cab], []
    tot = [0, 0, 0, 0]
    for m in D.MUTUOS:
        t = tm[m["contrato"]][ano]
        vals = [t["abertura"], t["captacao"], t["juros"], t["saldo"]]
        tot = [a + b for a, b in zip(tot, vals)]
        linhas.append([m["contrato"], D.ENTIDADES[m["mutuante"]]["curto"],
                       D.ENTIDADES[m["mutuaria"]]["curto"],
                       m["remuneracao"]] + [num(v, dash_zero=True) for v in vals])
    i = len(linhas)
    linhas.append(["TOTAL", "", "", ""] + [num(v) for v in tot])
    estilos.extend(_negrito(i))
    el.append(_tab(linhas, [24 * mm, 42 * mm, 42 * mm, 24 * mm, 30 * mm, 28 * mm, 36 * mm, 30 * mm],
                   estilos, fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        f"Nota — Os saldos conferem com os balanços das três empresas em 31/12/{ano}: no ativo não "
        "circulante da mutuante e no passivo não circulante da mutuária. Os juros são capitalizados "
        "sobre o saldo de abertura, à taxa do CDI do exercício "
        f"({pct(D.CDI[ano] * 100, 2)} em {ano}); a captação do ano não rende no próprio ano. Não há "
        "vencimento contratado nem garantia.", ST_NOTA))
    _assina(el, contador=CONTROLLER, diretor=None)
    build(d, el)
    return arquivo


# ------------------------------------------------------------------- AGING ---
def pdf_aging(titulo, linhas_aging, por_faixa, total, arquivo, coluna, notas=()):
    e = D.ENTIDADES["metalurgica"]
    d = doc(arquivo, paisagem=True)
    el = cabecalho(e["razao_social"], e["cnpj"], titulo, "Posição em 31 de dezembro de 2025", MIL)
    cab = [coluna] + X.FAIXAS + ["Total", "% do total"]
    linhas, estilos = [cab], []
    for nome, faixas, st in linhas_aging:
        # O nome do item em texto puro (ver o mapa de dívida): é ELE o rótulo da
        # linha, e ele tem de sair na mesma linha que os valores.
        linhas.append([nome] + [num(v, dash_zero=True) for v in faixas]
                      + [num(st), pct(st / total * 100)])
    i = len(linhas)
    linhas.append(["TOTAL"] + [num(v) for v in por_faixa] + [num(total), pct(100.0)])
    estilos.extend(_negrito(i))
    i = len(linhas)
    linhas.append(["% por faixa"] + [pct(v / total * 100) for v in por_faixa] + ["", ""])
    el.append(_tab(linhas, [100 * mm] + [22 * mm] * len(X.FAIXAS) + [22 * mm, 16 * mm],
                   estilos, fonte=6.6))
    el.append(Spacer(1, 3 * mm))
    for n in notas:
        el.append(Paragraph(n, ST_NOTA))
    el.append(Paragraph("A coluna <b>% do total</b> e a linha <b>% por faixa</b> são percentuais, "
                        "não valores monetários.", ST_NOTA))
    _assina(el, contador=CONTROLLER, diretor=None)
    build(d, el)
    return arquivo


# ----------------------------------------------------------------- EXTRATO ---
def pdf_extrato(bp, ano, arquivo):
    e = D.ENTIDADES["metalurgica"]
    meses, ini, fim = X.extrato(bp, ano)
    d = doc(arquivo)
    el = cabecalho("BANCO TAPAJÓS S.A.", None, "EXTRATO DE CONTA CORRENTE — RESUMO MENSAL",
                   f"Período: 01/01/{ano} a 31/12/{ano}", "Valores em REAIS (R$)",
                   f"Titular: {e['razao_social']} — CNPJ {e['cnpj']} — Agência 0418 — "
                   "Conta corrente 20.417-3")
    linhas, estilos = [["Mês", "Saldo inicial", "Créditos", "Débitos", "Saldo final"]], []
    for mes, s0, cr, db, s1 in meses:
        linhas.append([mes, reais(s0), reais(cr), reais(-db), reais(s1)])
    i = len(linhas)
    linhas.append(["TOTAL DO PERÍODO", reais(ini), reais(sum(m[2] for m in meses)),
                   reais(-sum(m[3] for m in meses)), reais(fim)])
    estilos.extend(_negrito(i))
    el.append(_tab(linhas, [34 * mm, 36 * mm, 38 * mm, 38 * mm, 36 * mm], estilos, fonte=7.4))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Débitos apresentados entre parênteses. Créditos compreendem liquidação de duplicatas, "
        "créditos de operações de desconto e transferências entre contas; débitos compreendem "
        "pagamentos a fornecedores, folha, tributos, juros e amortizações de empréstimos.", ST_NOTA))
    el.append(Paragraph("Extrato emitido para fins de conferência. Este documento não substitui o "
                        "extrato oficial disponível no canal eletrônico.", ST_NOTA))
    build(d, el)
    return arquivo


# ------------------------------------------------------------------- NOTAS ---
def pdf_notas(bp, tot, dre, arquivo):
    e = D.ENTIDADES["metalurgica"]
    t25, t24 = tot[2025]["metalurgica"], tot[2024]["metalurgica"]
    cov = X.covenant(bp, dre["metalurgica"])[2025]
    res25 = X.resultado(dre["metalurgica"][2025])
    ccl = t25["AC"] - t25["PC"]
    cp, reclass, _lp = X.saldos_emprestimos(2025)
    prov = X.valor(bp[2025]["holding"], "PNC", "Provisões", "Provisão para passivo a descoberto")
    imp = X.variacoes_met(bp)[2025]["impairment"]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "NOTAS EXPLICATIVAS ÀS DEMONSTRAÇÕES CONTÁBEIS",
                   "Exercício encerrado em 31 de dezembro de 2025",
                   "(Valores expressos em milhares de reais — R$ mil, salvo indicação em contrário)")

    def nota(titulo, texto):
        el.append(Paragraph(titulo, ST_H2))
        el.append(Paragraph(texto, ST_TXT))
        el.append(Spacer(1, 2 * mm))

    nota("1. CONTEXTO OPERACIONAL E CONTINUIDADE OPERACIONAL",
         "A Piraquara Metalúrgica e Estruturas Ltda. fabrica estruturas metálicas para galpões, "
         "torres e plantas industriais, e é controlada integralmente pela Piraquara Participações "
         f"S.A. No exercício de 2025 a Sociedade apurou prejuízo de R$ {num(abs(res25))} mil, "
         f"apresenta capital circulante líquido negativo de R$ {num(abs(ccl))} mil e patrimônio "
         f"líquido NEGATIVO (passivo a descoberto) de R$ {num(abs(t25['PL']))} mil, contra patrimônio "
         f"líquido positivo de R$ {num(t24['PL'])} mil em 31/12/2024. Esses fatos, somados ao "
         "descumprimento de cláusula restritiva descrito na Nota 3, indicam a existência de "
         "<b>incerteza relevante que levanta dúvida significativa sobre a capacidade de continuidade "
         "operacional</b> da Sociedade. A continuidade depende da repactuação da dívida bancária e "
         "do suporte financeiro da controladora e da parte relacionada Piraquara Montagens. As "
         "demonstrações foram preparadas no pressuposto de continuidade e não contemplam ajustes que "
         "seriam necessários caso esse pressuposto não se confirme.")
    nota("2. PASSIVO A DESCOBERTO",
         f"Em 31/12/2025 o passivo total excede o ativo total em R$ {num(abs(t25['PL']))} mil. A "
         "controladora, que avalia o investimento por equivalência patrimonial, mantém o investimento "
         f"por valor zero e registra provisão para passivo a descoberto de R$ {num(prov)} mil no seu "
         "passivo não circulante.")
    nota("3. EMPRÉSTIMOS E DESCUMPRIMENTO DE CLÁUSULA RESTRITIVA (COVENANT)",
         "Os contratos de capital de giro, conta garantida e cédula de crédito bancário preveem índice "
         f"máximo de Dívida Líquida / EBITDA de {vezes(D.COVENANT_LIMITE)}, apurado anualmente. Em "
         f"31/12/2025 a dívida líquida foi de R$ {num(cov['divida_liquida'])} mil e o EBITDA contratual "
         f"de R$ {num(cov['ebitda'])} mil, resultando em índice de <b>{vezes(cov['indice'])}</b>, "
         f"acima do limite: <b>o covenant foi ROMPIDO</b>. Conforme o CPC 26, os saldos de longo prazo "
         f"foram integralmente reclassificados para o passivo circulante (R$ {num(reclass)} mil), e o "
         "contrato de financiamento de máquinas, por vencimento cruzado, acompanhou a reclassificação. "
         "A composição está no quadro a seguir.")
    quadro = [["Empréstimos e financiamentos", "31/12/2025", "31/12/2024", "31/12/2023"]]
    for rot, idx in (("Circulante - cronograma original", 0), ("Circulante - reclassificado (covenant)", 1),
                     ("Não circulante", 2)):
        quadro.append([rot] + [num(X.saldos_emprestimos(a)[idx] or None) for a in (2025, 2024, 2023)])
    quadro.append(["Total"] + [num(X.divida_bancaria(a)) for a in (2025, 2024, 2023)])
    el.append(_tab(quadro, [80 * mm, 28 * mm, 28 * mm, 28 * mm], _negrito(len(quadro) - 1), fonte=7.4))
    el.append(Spacer(1, 2 * mm))
    nota("4. IMPAIRMENT",
         "A linha de laminação de perfis pesados, adquirida em 2024, foi paralisada em agosto de 2025. "
         f"O teste de recuperabilidade resultou em perda de R$ {num(imp)} mil, reconhecida no resultado "
         "operacional e excluída do EBITDA contratual por definição.")
    nota("5. PARTES RELACIONADAS",
         "A Sociedade mantém mútuos passivos com a controladora (contrato MUT-01/2021, 100% do CDI) e "
         "com a Piraquara Montagens e Serviços Industriais Ltda. (contrato MUT-02/2024, 105% do CDI), "
         "com juros capitalizados ao saldo e sem vencimento contratado.")
    nota("6. TRIBUTOS",
         "Em 2025 a Sociedade deixou de recolher parte do ICMS e das contribuições previdenciárias no "
         "vencimento e aderiu a parcelamento de tributos federais. Não foi reconhecido imposto de renda "
         "diferido ativo sobre prejuízos fiscais, dada a incerteza descrita na Nota 1.")
    nota("7. EVENTOS SUBSEQUENTES",
         "Em 18/02/2026 os credores declararam o vencimento antecipado dos contratos sujeitos ao "
         "covenant. Em 03/03/2026 a Sociedade firmou acordo de suspensão de cobrança (standstill) por "
         "90 dias com os bancos Tapajós e Cordilheira, para negociação de plano de repactuação.")
    _assina(el)
    build(d, el)
    return arquivo


def pdf_parecer(bp, tot, arquivo):
    e = D.ENTIDADES["metalurgica"]
    fornecedor = X.FORNECEDORES[0][0].split(" - ", 1)[1]
    d = doc(arquivo)
    el = cabecalho("LOBATO, TEIXEIRA & ASSOCIADOS AUDITORES INDEPENDENTES", "27.118.604/0001-90",
                   "RELATÓRIO DO AUDITOR INDEPENDENTE SOBRE AS DEMONSTRAÇÕES CONTÁBEIS",
                   "Exercício encerrado em 31 de dezembro de 2025", None)
    for titulo, texto in [
        ("OPINIÃO COM RESSALVA",
         f"Examinamos as demonstrações contábeis da {e['razao_social']}, que compreendem o balanço "
         "patrimonial em 31 de dezembro de 2025 e as respectivas demonstrações do resultado e dos "
         "fluxos de caixa para o exercício findo nessa data. Em nossa opinião, exceto pelos possíveis "
         "efeitos do assunto descrito na seção a seguir, as demonstrações contábeis apresentam "
         "adequadamente, em todos os aspectos relevantes, a posição patrimonial e financeira da "
         "Sociedade."),
        ("BASE PARA OPINIÃO COM RESSALVA",
         f"Não obtivemos resposta ao pedido de confirmação de saldo enviado ao fornecedor {fornecedor}, "
         "o maior credor comercial da Sociedade, cujo saldo está majoritariamente vencido há mais de "
         "90 dias, nem conseguimos satisfazer-nos por procedimentos alternativos quanto à existência "
         "de encargos moratórios não registrados sobre esse saldo."),
        ("INCERTEZA RELEVANTE RELACIONADA COM A CONTINUIDADE OPERACIONAL",
         "Chamamos a atenção para a Nota Explicativa 1, que descreve o prejuízo do exercício, o "
         "capital circulante líquido negativo, o patrimônio líquido negativo (passivo a descoberto) e "
         "o descumprimento do índice financeiro contratual, com vencimento antecipado da dívida "
         "bancária. Esses eventos indicam a existência de incerteza relevante que pode levantar dúvida "
         "significativa quanto à capacidade de continuidade operacional da Sociedade. Nossa opinião "
         "não está modificada em relação a esse assunto."),
    ]:
        el.append(Paragraph(titulo, ST_H2))
        el.append(Paragraph(texto, ST_TXT))
        el.append(Spacer(1, 2 * mm))
    el.append(Spacer(1, 5 * mm))
    el.append(Paragraph("Curitiba (PR), 20 de março de 2026.", ST_TXT))
    _assina(el, contador="Lobato, Teixeira & Associados — CRC 2PR-006.338/O-1",
            diretor="Renata S. Lobato — Contadora — CRC 1PR-054.207/O-8")
    build(d, el)
    return arquivo
