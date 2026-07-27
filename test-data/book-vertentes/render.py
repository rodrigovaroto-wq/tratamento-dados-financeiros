# -*- coding: utf-8 -*-
"""Renderiza o book em PDF com aparência de demonstração contábil de verdade."""

import os
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Table, TableStyle, Paragraph,
                                Spacer, KeepTogether)
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY

import dados as D
import motor as M
import demonstracoes as X

OUT = os.path.join(os.path.dirname(__file__), "pdf")
os.makedirs(OUT, exist_ok=True)

RODAPE_SINTETICO = ("Documento sintético, gerado para teste de sistema. Não corresponde a "
                    "empresa, pessoa ou fato real.")

ST_TIT = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=11, alignment=TA_CENTER, leading=14)
ST_SUB = ParagraphStyle("s", fontName="Helvetica", fontSize=8.5, alignment=TA_CENTER, leading=11)
ST_NOTA = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=7, leading=9)
ST_TXT = ParagraphStyle("p", fontName="Helvetica", fontSize=8.5, leading=12, alignment=TA_JUSTIFY)
ST_H2 = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=9, leading=13, spaceBefore=6)


def num(v, dash_zero=False):
    """Formato brasileiro; negativo entre PARÊNTESES (convenção contábil)."""
    if v is None:
        return ""
    if v == 0 and dash_zero:
        return "-"
    s = f"{abs(int(round(v))):,}".replace(",", ".")
    return f"({s})" if v < 0 else s


def cabecalho(entidade_nome, cnpj, titulo, periodo, escala):
    el = [Paragraph(entidade_nome, ST_TIT)]
    if cnpj:
        el.append(Paragraph(f"CNPJ {cnpj}", ST_SUB))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(titulo, ST_TIT))
    el.append(Paragraph(periodo, ST_SUB))
    el.append(Paragraph(escala, ST_SUB))
    el.append(Spacer(1, 4 * mm))
    return el


def doc(nome_arquivo, paisagem=False):
    return SimpleDocTemplate(
        os.path.join(OUT, nome_arquivo),
        pagesize=landscape(A4) if paisagem else A4,
        leftMargin=15 * mm, rightMargin=15 * mm, topMargin=14 * mm, bottomMargin=14 * mm,
        title=nome_arquivo.replace(".pdf", ""), author="Sistema sintético de teste",
    )


def tabela_bp(bp25, bp24, tot25, tot24, largura_rot=105 * mm):
    """Balanço detalhado comparativo: grupo → seção → subseção → conta."""
    linhas, estilos = [], []
    linhas.append(["", "31/12/2025", "31/12/2024"])
    estilos.extend([("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("LINEBELOW", (0, 0), (-1, 0), 0.7, colors.black),
                    ("ALIGN", (1, 0), (-1, -1), "RIGHT")])
    i = 1

    def add(rot, v25, v24, estilo=None, indent=0):
        nonlocal i
        linhas.append(["  " * indent + rot, num(v25), num(v24)])
        if estilo == "grupo":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black),
                            ("BACKGROUND", (0, i), (-1, i), colors.Color(.90, .90, .90))])
        elif estilo == "secao":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold")])
        elif estilo == "sub":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Oblique"),
                            ("TEXTCOLOR", (0, i), (-1, i), colors.Color(.25, .25, .25))])
        elif estilo == "total":
            estilos.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                            ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1

    def bloco(secoes, rotulo_grupo, chave_total):
        add(rotulo_grupo, tot25[chave_total], tot24[chave_total], "grupo")
        for sec_key, label in secoes:
            add(label, tot_secao(bp25, sec_key), tot_secao(bp24, sec_key), "secao")
            for sub in bp25[sec_key]:
                contas25 = {r: v for r, v in bp25[sec_key][sub]}
                contas24 = {r: v for r, v in bp24[sec_key].get(sub, [])}
                if not contas25 and not contas24:
                    continue
                add(sub, sum(contas25.values()), sum(contas24.values()), "sub", 1)
                for rot in contas25:
                    add(rot, contas25.get(rot), contas24.get(rot), None, 2)
                for rot in contas24:
                    if rot not in contas25:
                        add(rot, None, contas24[rot], None, 2)

    def tot_secao(bp, sec):
        return M.soma_folhas(bp[sec])

    bloco([("AC", "Ativo Circulante"), ("ANC", "Ativo Não Circulante")], "ATIVO", "ATIVO")
    add("TOTAL DO ATIVO", tot25["ATIVO"], tot24["ATIVO"], "total")
    linhas.append(["", "", ""]); i += 1
    add("PASSIVO E PATRIMÔNIO LÍQUIDO", tot25["PASSIVO_PL"], tot24["PASSIVO_PL"], "grupo")
    for sec_key, label in [("PC", "Passivo Circulante"), ("PNC", "Passivo Não Circulante")]:
        add(label, tot_secao(bp25, sec_key), tot_secao(bp24, sec_key), "secao")
        for sub in bp25[sec_key]:
            c25 = {r: v for r, v in bp25[sec_key][sub]}
            c24 = {r: v for r, v in bp24[sec_key].get(sub, [])}
            if not c25 and not c24:
                continue
            add(sub, sum(c25.values()) if c25 else None, sum(c24.values()) if c24 else None, "sub", 1)
            for rot in c25:
                add(rot, c25.get(rot), c24.get(rot), None, 2)
            for rot in c24:
                if rot not in c25:
                    add(rot, None, c24[rot], None, 2)
    add("Patrimônio Líquido", tot25["PL"], tot24["PL"], "secao")
    for sub in bp25["PL"]:
        c25 = {r: v for r, v in bp25["PL"][sub]}
        c24 = {r: v for r, v in bp24["PL"].get(sub, [])}
        add(sub, sum(c25.values()), sum(c24.values()), "sub", 1)
        for rot in c25:
            add(rot, c25.get(rot), c24.get(rot), None, 2)
    add("TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", tot25["PASSIVO_PL"], tot24["PASSIVO_PL"], "total")

    t = Table(linhas, colWidths=[largura_rot, 32 * mm, 32 * mm], repeatRows=1)
    estilos.extend([("FONTNAME", (0, 1), (-1, -1), "Helvetica"), ("FONTSIZE", (0, 0), (-1, -1), 7.4),
                    ("TOPPADDING", (0, 0), (-1, -1), 1.1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.1),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE")])
    t.setStyle(TableStyle(estilos))
    return t


def pdf_balanco(chave, bp, tot, arquivo, nota_extra=None):
    e = D.ENTIDADES[chave]
    d = doc(arquivo)
    el = cabecalho(e["razao_social"], e["cnpj"], "BALANÇO PATRIMONIAL",
                   "Exercícios encerrados em 31 de dezembro de 2025 e de 2024",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(tabela_bp(bp[2025][chave], bp[2024][chave], tot[2025][chave], tot[2024][chave]))
    el.append(Spacer(1, 4 * mm))
    if nota_extra:
        el.append(Paragraph(nota_extra, ST_NOTA))
        el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("As notas explicativas são parte integrante das demonstrações contábeis.", ST_NOTA))
    el.append(Spacer(1, 6 * mm))
    el.append(Paragraph("_______________________________________", ST_NOTA))
    el.append(Paragraph("Marcos A. Ferreira — Contador — CRC 1SP-214.887/O-3", ST_NOTA))
    el.append(Paragraph("Helena R. Vertentes — Diretora Administrativa — CPF 123.456.789-00", ST_NOTA))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(RODAPE_SINTETICO, ST_NOTA))
    d.build(el)
    return arquivo


def _tab(linhas, larguras, estilos_extra=(), fonte=7.4, repeat=1):
    t = Table(linhas, colWidths=larguras, repeatRows=repeat)
    est = [("FONTSIZE", (0, 0), (-1, -1), fonte), ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
           ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
           ("LINEBELOW", (0, 0), (-1, 0), 0.7, colors.black),
           ("TOPPADDING", (0, 0), (-1, -1), 1.1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.1),
           ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]
    est.extend(estilos_extra)
    t.setStyle(TableStyle(est))
    return t


def _assina(el, extra=None):
    el.append(Spacer(1, 5 * mm))
    if extra:
        el.append(Paragraph(extra, ST_NOTA)); el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("_______________________________________", ST_NOTA))
    el.append(Paragraph("Marcos A. Ferreira — Contador — CRC 1SP-214.887/O-3", ST_NOTA))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph(RODAPE_SINTETICO, ST_NOTA))


# ---------------------------------------------------------------- COMBINADO --
SUBS_PADRAO = {
    "AC": ["Disponível", "Contas a Receber", "Estoques", "Tributos a Recuperar", "Outros Créditos"],
    "ANC": ["Realizável a Longo Prazo", "Investimentos", "Imobilizado", "Intangível"],
    "PC": ["Fornecedores", "Empréstimos e Financiamentos", "Arrendamentos",
           "Obrigações Trabalhistas e Sociais", "Obrigações Tributárias", "Partes Relacionadas",
           "Outras Obrigações"],
    "PNC": ["Empréstimos e Financiamentos", "Obrigações Tributárias", "Provisões", "Arrendamentos"],
}


def pdf_combinado(bp, tot, ano, arquivo):
    c = M.combinado(bp, tot, ano)
    ordem = c["ordem"]
    nomes = ["Vertentes Part.", "Metalúrgica", "Componentes", "VT Logística", "Imóveis SPE"]
    elim = dict(M.eliminacoes(bp, tot, ano))
    mut = elim["Mútuos holding × controladas"]
    cc = elim["Conta corrente Metalúrgica × VT Logística"]
    alug = elim["Aluguéis SPE × Metalúrgica"]

    def sub_val(ent, sec, sub):
        return sum(v for _, v in bp[ano][ent][sec].get(sub, []))

    ELIM = {("AC", "Outros Créditos"): -(cc + alug),
            ("ANC", "Realizável a Longo Prazo"): -mut,
            ("ANC", "Investimentos"): -c["elim_invest"],
            ("PC", "Partes Relacionadas"): -(mut + cc),
            ("PC", "Outras Obrigações"): -alug,
            ("PNC", "Provisões"): -c["elim_provisao"]}

    linhas = [["", *nomes, "Eliminações", "Combinado"]]
    est, i = [], 1

    def add(rot, vals, elim_v, total, estilo=None, indent=0):
        nonlocal i
        linhas.append(["  " * indent + rot, *[num(v) for v in vals], num(elim_v), num(total)])
        if estilo == "grupo":
            est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                        ("BACKGROUND", (0, i), (-1, i), colors.Color(.90, .90, .90)),
                        ("LINEABOVE", (0, i), (-1, i), 0.5, colors.black)])
        elif estilo == "secao":
            est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold")])
        elif estilo == "total":
            est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                        ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1

    def bloco_secao(sec, label):
        vals_sec = [M.soma_folhas(bp[ano][e][sec]) for e in ordem]
        elim_sec = sum(v for (s, _), v in ELIM.items() if s == sec)
        add(label, vals_sec, elim_sec or None, sum(vals_sec) + elim_sec, "secao")
        for sub in SUBS_PADRAO[sec]:
            vals = [sub_val(e, sec, sub) for e in ordem]
            if not any(vals):
                continue
            ev = ELIM.get((sec, sub))
            add(sub, vals, ev, sum(vals) + (ev or 0), None, 1)

    add("ATIVO", [tot[ano][e]["ATIVO"] for e in ordem],
        -(c["elim_invest"] + c["elim_mutuos"]), c["ativo"], "grupo")
    bloco_secao("AC", "Ativo Circulante")
    bloco_secao("ANC", "Ativo Não Circulante")
    add("TOTAL DO ATIVO", [tot[ano][e]["ATIVO"] for e in ordem],
        -(c["elim_invest"] + c["elim_mutuos"]), c["ativo"], "total")
    linhas.append([""] * 8); i += 1
    add("PASSIVO E PATRIMÔNIO LÍQUIDO", [tot[ano][e]["PASSIVO_PL"] for e in ordem],
        -(c["elim_invest"] + c["elim_mutuos"]), c["ativo"], "grupo")
    bloco_secao("PC", "Passivo Circulante")
    bloco_secao("PNC", "Passivo Não Circulante")
    add("Patrimônio Líquido", [tot[ano][e]["PL"] for e in ordem], None, None, "secao")
    pl_subs = sum(tot[ano][e]["PL"] for e in ordem if e != "holding")
    add("(-) Eliminação do patrimônio líquido das controladas", [None] * 5, -pl_subs, -pl_subs, None, 1)
    add("Participação de não controladores (VT Logística — 30%)", [None] * 5, None, c["nci"], None, 1)
    add("TOTAL DO PATRIMÔNIO LÍQUIDO", [None] * 5, None, c["pl"], "total")
    add("TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", [None] * 5, None, c["passivo"] + c["pl"], "total")

    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.GRUPO, None, "BALANÇO PATRIMONIAL COMBINADO",
                   f"Em 31 de dezembro de {ano} — com colunas por entidade, eliminações intragrupo e "
                   "participação de não controladores",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [92 * mm] + [24 * mm] * 7, est, fonte=7.0))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "As eliminações compreendem: (i) os investimentos avaliados por equivalência patrimonial contra o "
        "patrimônio líquido das controladas; (ii) a provisão para passivo a descoberto da Vertentes "
        "Componentes Automotivos Ltda.; e (iii) os saldos recíprocos de mútuos, conta corrente e aluguéis "
        "entre as entidades do grupo.", ST_NOTA))
    _assina(el)
    d.build(el)
    return arquivo


# --------------------------------------------------------------------- DRE ---
def pdf_dre(tot, arquivo):
    l25, v24, _ = X.dre_metalurgica(tot)
    c25, res25 = X.cascata(l25)
    c24, res24 = X.cascata(l25, v24)
    linhas = [["", "2025", "2024"]]
    est, i = [], 1
    for (rot, v25, tipo), (_, v24v, _t) in zip(c25, c24):
        linhas.append([("" if tipo == "sub" else "    ") + rot, num(v25), num(v24v)])
        if tipo == "sub":
            est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                        ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))])
        elif tipo == "ancora":
            est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                        ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
        i += 1
    d = doc(arquivo)
    e = D.ENTIDADES["metalurgica"]
    el = cabecalho(e["razao_social"], e["cnpj"], "DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO",
                   "Exercícios encerrados em 31 de dezembro de 2025 e de 2024",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [110 * mm, 30 * mm, 30 * mm], est))
    _assina(el, "As notas explicativas são parte integrante das demonstrações contábeis.")
    d.build(el)
    return arquivo


# --------------------------------------------------------------------- DFC ---
def pdf_dfc(tot, prejuizo, arquivo):
    f = X.dfc_metalurgica(tot, prejuizo)
    linhas = [["", "2025"]]
    est, i = [], 1

    def sec(rot):
        nonlocal i
        linhas.append([rot, ""])
        est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("BACKGROUND", (0, i), (-1, i), colors.Color(.93, .93, .93))]); i += 1

    def item(rot, v):
        nonlocal i
        linhas.append(["    " + rot, num(v)]); i += 1

    def anc(rot, v):
        nonlocal i
        linhas.append([rot, num(v)])
        est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                    ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)]); i += 1

    sec("FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS")
    for r, v in f["operacional"]: item(r, v)
    anc("Caixa líquido gerado pelas (aplicado nas) atividades operacionais", f["tot_op"])
    sec("FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO")
    for r, v in f["investimento"]: item(r, v)
    anc("Caixa líquido aplicado nas atividades de investimento", f["tot_inv"])
    sec("FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO")
    for r, v in f["financiamento"]: item(r, v)
    anc("Caixa líquido gerado pelas (aplicado nas) atividades de financiamento", f["tot_fin"])
    anc("REDUÇÃO LÍQUIDA DE CAIXA E EQUIVALENTES DE CAIXA", f["variacao"])
    item("Caixa e equivalentes de caixa no início do exercício", f["caixa_ini"])
    item("Caixa e equivalentes de caixa no final do exercício", f["caixa_fim"])

    d = doc(arquivo)
    e = D.ENTIDADES["metalurgica"]
    el = cabecalho(e["razao_social"], e["cnpj"],
                   "DEMONSTRAÇÃO DOS FLUXOS DE CAIXA — MÉTODO INDIRETO",
                   "Exercício encerrado em 31 de dezembro de 2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [130 * mm, 32 * mm], est))
    _assina(el, "O saldo final de caixa e equivalentes confere com a rubrica Disponível do balanço patrimonial.")
    d.build(el)
    return arquivo


# -------------------------------------------------------------------- DMPL ---
def pdf_dmpl(tot, prejuizo, arquivo):
    t24, t25 = tot[2024]["metalurgica"], tot[2025]["metalurgica"]
    cap, capint, rl, aap = 45000, -2000, 1200, 1850
    linhas = [["", "Capital social", "Capital a integralizar", "Reserva legal",
               "Ajuste de avaliação patrimonial", "Prejuízos acumulados", "Total"]]
    est = []
    linhas.append(["SALDOS EM 31 DE DEZEMBRO DE 2024", num(cap), num(capint), num(rl), num(aap),
                   num(t24["plug"]), num(t24["PL"])])
    est.append(("FONTNAME", (0, 1), (-1, 1), "Helvetica-Bold"))
    linhas.append(["Prejuízo líquido do exercício", "-", "-", "-", "-", num(prejuizo), num(prejuizo)])
    linhas.append(["SALDOS EM 31 DE DEZEMBRO DE 2025", num(cap), num(capint), num(rl), num(aap),
                   num(t25["plug"]), num(t25["PL"])])
    est.extend([("FONTNAME", (0, 3), (-1, 3), "Helvetica-Bold"),
                ("LINEABOVE", (0, 3), (-1, 3), 0.4, colors.black)])
    d = doc(arquivo, paisagem=True)
    e = D.ENTIDADES["metalurgica"]
    el = cabecalho(e["razao_social"], e["cnpj"],
                   "DEMONSTRAÇÃO DAS MUTAÇÕES DO PATRIMÔNIO LÍQUIDO",
                   "Exercício encerrado em 31 de dezembro de 2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [62 * mm, 26 * mm, 30 * mm, 24 * mm, 34 * mm, 30 * mm, 26 * mm], est, fonte=7.0))
    _assina(el)
    d.build(el)
    return arquivo


# ------------------------------------------------------------- FATURAMENTO ---
def pdf_faturamento(fat, t24, t25, arquivo):
    linhas = [["Mês", "2024", "2025", "Variação %"]]
    est, i = [], 1
    for mes, v24, v25 in fat:
        var = (v25 / v24 - 1) * 100 if v24 else 0
        linhas.append([f"{mes}/2024 — {mes}/2025", num(v24), num(v25), f"{var:+.1f}%"])
        i += 1
    linhas.append(["TOTAL DO EXERCÍCIO", num(t24), num(t25), f"{(t25/t24-1)*100:+.1f}%"])
    est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
    linhas.append(["Média mensal", num(t24 // 12), num(t25 // 12), ""])
    linhas.append(["Ticket médio por pedido (R$ mil) — indicador gerencial", "38,2", "31,4", "-17,8%"])
    d = doc(arquivo)
    e = D.ENTIDADES["metalurgica"]
    el = cabecalho(e["razao_social"], e["cnpj"], "FATURAMENTO MENSAL — ÚLTIMOS 24 MESES",
                   "Período: janeiro/2024 a dezembro/2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [78 * mm, 30 * mm, 30 * mm, 28 * mm], est, fonte=8))
    _assina(el, "O total do exercício de 2025 confere com a Receita Operacional Bruta da demonstração do resultado.")
    d.build(el)
    return arquivo


# ------------------------------------------------------------ MAPA DÍVIDA ---
def pdf_mapa_divida(contratos, arquivo):
    """EM REAIS (unidades) — escala diferente das demonstrações, de propósito."""
    linhas = [["Credor", "Modalidade", "Saldo devedor (R$)", "Taxa", "Vencimento", "Garantia", "Juros do exercício (R$)"]]
    est, i = [], 1
    for credor, mod, saldo_mil, taxa, venc, gar, juros_mil in contratos:
        linhas.append([credor, mod, num(saldo_mil * 1000), taxa, venc, gar, num(juros_mil * 1000)])
        i += 1
    tot_s = sum(c[2] for c in contratos) * 1000
    tot_j = sum(c[6] for c in contratos) * 1000
    linhas.append(["TOTAL", "", num(tot_s), "", "", "", num(tot_j)])
    est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
    est.append(("ALIGN", (1, 1), (1, -1), "LEFT"))
    est.append(("ALIGN", (3, 1), (5, -1), "LEFT"))
    d = doc(arquivo, paisagem=True)
    e = D.ENTIDADES["metalurgica"]
    el = cabecalho(e["razao_social"], e["cnpj"], "MAPA DE ENDIVIDAMENTO BANCÁRIO E FINANCEIRO",
                   "Posição em 31 de dezembro de 2025",
                   "(Valores expressos em REAIS — R$)")
    el.append(_tab(linhas, [52 * mm, 38 * mm, 30 * mm, 32 * mm, 26 * mm, 55 * mm, 28 * mm], est, fonte=6.6))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Atenção: os valores deste mapa estão expressos em REAIS, enquanto as demonstrações contábeis "
        "estão em milhares de reais. Covenant de cobertura de juros descumprido em 31/12/2025 no contrato "
        "de capital de giro do Banco Meridional S.A., o que autoriza o vencimento antecipado da dívida.", ST_NOTA))
    _assina(el)
    d.build(el)
    return arquivo


# ----------------------------------------------------------------- MÚTUOS ---
def pdf_mutuos(mut, total, tot, arquivo):
    linhas = [["Credora (mutuante)", "Devedora (mutuária)", "Natureza", "Saldo (R$ mil)", "Vencimento"]]
    est, i = [], 1
    for cred, dev, nat, val, venc in mut:
        linhas.append([cred, dev, nat, num(val), venc]); i += 1
    linhas.append(["TOTAL", "", "", num(total), ""])
    est.extend([("FONTNAME", (0, i), (-1, i), "Helvetica-Bold"),
                ("LINEABOVE", (0, i), (-1, i), 0.4, colors.black)])
    est.extend([("ALIGN", (0, 1), (2, -1), "LEFT"), ("ALIGN", (4, 1), (4, -1), "LEFT")])
    d = doc(arquivo, paisagem=True)
    el = cabecalho(D.GRUPO, None, "RELAÇÃO DE MÚTUOS E CONTAS INTRAGRUPO",
                   "Posição em 31 de dezembro de 2025",
                   "(Valores expressos em milhares de reais — R$ mil)")
    el.append(_tab(linhas, [62 * mm, 62 * mm, 34 * mm, 28 * mm, 40 * mm], est, fonte=7.4))
    el.append(Spacer(1, 3 * mm))
    el.append(Paragraph(
        "Controle mantido pela administração em planilha auxiliar. Os saldos podem apresentar pequenas "
        "diferenças em relação aos registros contábeis das entidades em razão de lançamentos em trânsito.", ST_NOTA))
    _assina(el)
    d.build(el)
    return arquivo


# -------------------------------------------------------------- BALANCETE ---
def pdf_balancete(bp, arquivo):
    """Balancete analítico com colunas DÉBITO/CRÉDITO e natureza do saldo (D/C)."""
    e = D.ENTIDADES["componentes"]
    b = bp[2025]["componentes"]
    linhas = [["Código", "Conta", "Saldo anterior", "Débitos", "Créditos", "Saldo atual", "D/C"]]
    est, i = [], 1
    cod_sec = {"AC": "1.1", "ANC": "1.2", "PC": "2.1", "PNC": "2.2", "PL": "2.3"}
    ndeb = ("AC", "ANC")
    for sec in ("AC", "ANC", "PC", "PNC", "PL"):
        n = 0
        for sub, contas in b[sec].items():
            n += 1
            m = 0
            for rot, v in contas:
                m += 1
                cod = f"{cod_sec[sec]}.{n:02d}.{m:03d}"
                deb = int(abs(v) * 0.62)
                cre = int(abs(v) * 0.41)
                ant = abs(v) - deb + cre
                natureza = "D" if (sec in ndeb) != (v < 0) else "C"
                linhas.append([cod, rot, num(ant), num(deb), num(cre), num(abs(v)), natureza])
                i += 1
    est.extend([("ALIGN", (1, 1), (1, -1), "LEFT"), ("ALIGN", (6, 1), (6, -1), "CENTER"),
                ("FONTSIZE", (0, 0), (-1, -1), 6.4)])
    d = doc(arquivo, paisagem=True)
    el = cabecalho(e["razao_social"], e["cnpj"], "BALANCETE ANALÍTICO",
                   "Movimento acumulado de 01/01/2025 a 31/12/2025",
                   "(Valores em R$ mil — saldos com indicação de natureza devedora (D) ou credora (C))")
    el.append(_tab(linhas, [26 * mm, 92 * mm, 26 * mm, 26 * mm, 26 * mm, 26 * mm, 12 * mm], est, fonte=6.4))
    _assina(el)
    d.build(el)
    return arquivo


# ------------------------------------------------------------------ NOTAS ---
def pdf_notas(tot, arquivo):
    t25, t24 = tot[2025]["metalurgica"], tot[2024]["metalurgica"]
    c25 = M.combinado(*M.construir(), 2025) if False else None
    d = doc(arquivo)
    el = cabecalho(D.GRUPO, None, "NOTAS EXPLICATIVAS ÀS DEMONSTRAÇÕES CONTÁBEIS",
                   "Exercício encerrado em 31 de dezembro de 2025", "")
    def h(t): el.append(Paragraph(t, ST_H2))
    def p(t): el.append(Paragraph(t, ST_TXT))
    h("1. Contexto operacional e continuidade operacional (going concern)")
    p("O Grupo Vertentes atua na fabricação de componentes metálicos e usinados para as cadeias "
      "automotiva e de bens de capital, por meio de cinco entidades sob controle comum. No exercício "
      f"encerrado em 31 de dezembro de 2025 a controlada operacional apurou prejuízo líquido de "
      f"R$ {abs(t25['plug']-t24['plug']):,} mil".replace(",", ".") +
      f" e apresentava capital circulante líquido NEGATIVO de R$ {abs(t25['AC']-t25['PC']):,} mil".replace(",", ".") +
      ", além de índice de liquidez corrente de "
      f"{t25['AC']/t25['PC']:.2f}".replace(".", ",") +
      ". A controlada Vertentes Componentes Automotivos Ltda. apresenta PASSIVO A DESCOBERTO. "
      "Essas condições indicam incerteza significativa quanto à capacidade de continuidade operacional. "
      "A administração vem negociando com credores financeiros o alongamento do perfil da dívida, "
      "avaliou a alienação de ativos não operacionais e contratou assessoria financeira independente "
      "para estruturar uma reorganização. As demonstrações contábeis foram elaboradas no pressuposto "
      "de continuidade, o qual depende do êxito dessas medidas.")
    h("2. Descumprimento de cláusulas restritivas (covenants)")
    p("Em 31 de dezembro de 2025 a Companhia não atendia ao índice mínimo de cobertura de juros "
      "(EBITDA/Despesa financeira líquida ≥ 1,5x) previsto no contrato de capital de giro mantido com o "
      "Banco Meridional S.A. Em razão do descumprimento, e por não haver waiver formal obtido até a data "
      "de aprovação destas demonstrações, a parcela do saldo classificada no passivo não circulante foi "
      "RECLASSIFICADA para o passivo circulante, conforme requerido pelas práticas contábeis adotadas no "
      "Brasil. A reclassificação não altera as condições contratuais de vencimento originais.")
    h("3. Parcelamentos tributários")
    p("O Grupo mantém débitos tributários federais e estaduais em programas de parcelamento. Parcelas "
      "vencidas e não pagas em dezembro de 2025 podem implicar a rescisão dos programas e a exigibilidade "
      "imediata do saldo, hipótese não provisionada por ser considerada, pela administração, de "
      "probabilidade possível e não provável.")
    h("4. Partes relacionadas")
    p("As operações entre as entidades do grupo compreendem mútuos sem remuneração e sem vencimento "
      "definido, contas correntes de rateio de despesas e a locação de galpões industriais pela Vertentes "
      "Imóveis SPE Ltda. às demais entidades. Os saldos recíprocos são eliminados nas demonstrações "
      "combinadas.")
    h("5. Provisões e passivos contingentes")
    p("As provisões trabalhistas e cíveis foram constituídas com base na avaliação dos assessores "
      "jurídicos para as causas com perda provável. Existem, adicionalmente, causas de perda possível "
      "não provisionadas, cujo montante estimado não é individualmente relevante.")
    h("6. Eventos subsequentes")
    p("Em 12 de fevereiro de 2026 a Companhia recebeu notificação extrajudicial de fornecedor relevante "
      "exigindo o pagamento de valores em atraso, com ameaça de suspensão do fornecimento de insumo "
      "crítico. A administração está negociando um plano de pagamento.")
    _assina(el)
    d.build(el)
    return arquivo
