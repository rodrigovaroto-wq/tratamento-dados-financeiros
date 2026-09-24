# -*- coding: utf-8 -*-
"""Demonstrações e anexos do book PIRAQUARA, TODOS amarrados ao balanço.

A regra desta camada é a mesma do `book-canastra`: **nenhum documento digita um
total que já existe no balanço**. Depreciação, PECLD, perdas em estoque,
provisões e impairment da DRE são a VARIAÇÃO da conta retificadora; os juros
bancários da DRE são a soma dos juros do mapa de dívida; os juros de mútuo são
os mesmos nas duas DREs; o aging soma a conta do balanço; o extrato termina no
caixa. Se um número deixar de bater, o `assert` derruba a geração.

Diferença de desenho em relação ao canastra, e ela é deliberada: aqui a DRE NÃO
tem linha de "outras receitas (despesas)" que absorve a diferença até o PL. A
DRE é montada inteira, o resultado dela É a variação do PL, e quem fecha o
balanço de 2024 e 2025 é o Disponível — que a DFC depois reconstrói linha a
linha, sem rubrica de ajuste. É a forma mais dura de provar que as três
demonstrações contam a mesma história.

Este módulo não importa `motor` (o motor é quem o importa, para saber o
resultado antes de fechar o caixa). As leituras de balanço são locais.
"""

import hashlib

import dados as D

ANOS = D.ANOS


# ------------------------------------------------------------ LEITURAS -------
def soma(contas):
    return sum(v for _, v in contas)


def soma_secao(secao_dict):
    return sum(soma(v) for v in secao_dict.values() if v != D.PLUG)


def valor(bp_ent, secao, sub, prefixo):
    for rot, v in bp_ent[secao].get(sub, []):
        if rot.startswith(prefixo):
            return v
    return 0


def _anterior(ano):
    i = ANOS.index(ano)
    return ANOS[i - 1] if i else None


def _reparte(total, pesos):
    """Reparte `total` (inteiro) pelos pesos, com o último absorvendo o
    arredondamento — assim a soma das partes é o total, sem exceção."""
    partes, acum = [], 0
    for i, p in enumerate(pesos):
        v = total - acum if i == len(pesos) - 1 else int(round(total * p))
        partes.append(v)
        acum += v
    assert sum(partes) == total
    return partes


# --------------------------------------------------- DÍVIDA E MÚTUOS ---------
def saldos_emprestimos(ano):
    """(circulante, reclassificado, não circulante) da Metalúrgica, em R$ mil.

    Até 2024 cada contrato divide o saldo pela fração `cp`. Em 2025 o covenant
    rompido antecipa o vencimento: o que já era circulante continua na linha
    circulante, o resto vai para a linha de reclassificação, e o não circulante
    DEIXA DE EXISTIR (conta ausente, não zero)."""
    cp = reclass = lp = 0
    for k in D.CONTRATOS:
        s = k["saldos"].get(ano)
        if s is None:
            continue
        parte_cp = int(round(s * k["cp"]))
        if ano == 2025:
            cp += parte_cp
            reclass += s - parte_cp
        else:
            cp += parte_cp
            lp += s - parte_cp
    return cp, reclass, lp


def divida_bancaria(ano):
    return sum(k["saldos"].get(ano, 0) for k in D.CONTRATOS)


def juros_contrato(k, ano):
    """Juros do exercício sobre o saldo MÉDIO (abertura + fechamento)/2. O saldo
    de abertura de 2023 é o declarado em `SALDO_2022`; contrato que nasce no ano
    abre em zero."""
    s = k["saldos"].get(ano)
    if s is None:
        return 0
    ant = _anterior(ano)
    abertura = D.SALDO_2022.get(k["contrato"], 0) if ant is None else k["saldos"].get(ant, 0)
    return int(round((abertura + s) / 2 * k["taxa_efetiva"][ano]))


def juros_bancarios(ano):
    return sum(juros_contrato(k, ano) for k in D.CONTRATOS)


def mutuos_tabela():
    """{contrato: {ano: {abertura, captacao, juros, saldo}}}. Juros capitalizados
    sobre o saldo de abertura."""
    out = {}
    for m in D.MUTUOS:
        saldo = m["saldo_2022"]
        por_ano = {}
        for ano in ANOS:
            juros = int(round(saldo * D.CDI[ano] * m["fator_cdi"]))
            cap = m["captacoes"][ano]
            novo = saldo + cap + juros
            por_ano[ano] = {"abertura": saldo, "captacao": cap, "juros": juros, "saldo": novo}
            saldo = novo
        out[m["contrato"]] = por_ano
    return out


def juros_mutuo(contrato, ano):
    return mutuos_tabela()[contrato][ano]["juros"]


def saldo_mutuo(contrato, ano):
    return mutuos_tabela()[contrato][ano]["saldo"]


# --------------------------------------------------------- VARIAÇÕES ---------
def variacoes_met(bp):
    """Movimentos não caixa LIDOS do balanço da Metalúrgica. 2023 é declarado
    (não há balanço de 2022 no book)."""
    v = {2023: dict(D.VARIACOES_2023_MET)}
    for ano in ANOS[1:]:
        ant = _anterior(ano)
        m, a = bp[ano]["metalurgica"], bp[ant]["metalurgica"]
        v[ano] = {
            "depreciacao": -valor(m, "ANC", "Imobilizado", "(-) Depreciação acumulada")
                           + valor(a, "ANC", "Imobilizado", "(-) Depreciação acumulada"),
            "impairment": -valor(m, "ANC", "Imobilizado", "(-) Perda por redução")
                          + valor(a, "ANC", "Imobilizado", "(-) Perda por redução"),
            "pecld": -valor(m, "AC", "Contas a Receber", "(-) Perdas estimadas")
                     + valor(a, "AC", "Contas a Receber", "(-) Perdas estimadas"),
            "estoques": -valor(m, "AC", "Estoques", "(-) Provisão para perdas")
                        + valor(a, "AC", "Estoques", "(-) Provisão para perdas"),
            "contingencias": soma(m["PNC"].get("Provisões", [])) - soma(a["PNC"].get("Provisões", [])),
        }
    return v


# ------------------------------------------------------------- DRE MET -------
def dre_metalurgica(bp):
    """{ano: [(rótulo, valor, tipo)]}, tipo em conta | subtotal | ancora.
    Despesa sai NEGATIVA. O resultado é o que a cascata dá — nada absorve."""
    var = variacoes_met(bp)
    out = {}
    for ano in ANOS:
        rb = D.RECEITA_BRUTA_MET[ano]
        mx = D.MIX_MET[ano]
        icms, pis, dev = -round(rb * .165), -round(rb * .0925), -round(rb * .012)
        rl = rb + icms + pis + dev
        dep = var[ano]["depreciacao"]
        dep_ind = round(dep * .80)
        dep_adm = dep - dep_ind

        custo = [
            ("(-) Custo de materiais, mão de obra e gastos gerais de fabricação",
             -round(rl * mx["cpv"])),
            ("(-) Depreciação industrial", -dep_ind),
        ]
        lucro_bruto = rl + soma(custo)
        desp = [
            ("(-) Despesas com vendas e fretes", -round(rl * mx["vendas"])),
            ("(-) Despesas gerais e administrativas", -round(rl * mx["ga"])),
            ("(-) Depreciação administrativa", -dep_adm),
            ("(-) Perdas estimadas em créditos de liquidação duvidosa", -var[ano]["pecld"]),
            ("(-) Provisão para perdas em estoques", -var[ano]["estoques"]),
            ("(-) Provisão para contingências trabalhistas e tributárias",
             -var[ano]["contingencias"]),
        ]
        if var[ano]["impairment"]:
            desp.append(("(-) Perda por redução ao valor recuperável do imobilizado (impairment)",
                         -var[ano]["impairment"]))
        ebit = lucro_bruto + soma(desp)

        rec_fin = [
            ("Rendimentos de aplicações financeiras", D.FIN_MET["rendimentos"][ano]),
            ("Descontos obtidos", D.FIN_MET["descontos"][ano]),
        ]
        juros_mut = juros_mutuo("MUT-01/2021", ano) + juros_mutuo("MUT-02/2024", ano)
        desp_fin = [
            ("(-) Juros sobre empréstimos e financiamentos bancários", -juros_bancarios(ano)),
            ("(-) Juros sobre mútuos com partes relacionadas", -juros_mut),
            ("(-) Juros e multas moratórias sobre tributos e fornecedores",
             -D.FIN_MET["multas"][ano]),
            ("(-) IOF, tarifas bancárias e comissões de fiança", -D.FIN_MET["tarifas"][ano]),
        ]
        res_fin = soma(rec_fin) + soma(desp_fin)
        lair = ebit + res_fin
        ir = -int(round(lair * D.ALIQUOTA_IR)) if lair > 0 else 0
        liquido = lair + ir

        linhas = [("RECEITA OPERACIONAL BRUTA", rb, "ancora"),
                  ("Venda de estruturas metálicas", round(rb * .74), "conta"),
                  ("Venda de peças, perfis e componentes", round(rb * .21), "conta"),
                  ("Serviços de corte, dobra e pintura",
                   rb - round(rb * .74) - round(rb * .21), "conta"),
                  ("(-) DEDUÇÕES DA RECEITA BRUTA", icms + pis + dev, "subtotal"),
                  ("(-) ICMS e IPI sobre vendas", icms, "conta"),
                  ("(-) PIS e COFINS sobre vendas", pis, "conta"),
                  ("(-) Devoluções e abatimentos", dev, "conta"),
                  ("RECEITA OPERACIONAL LÍQUIDA", rl, "ancora"),
                  ("(-) CUSTO DOS PRODUTOS VENDIDOS", soma(custo), "subtotal")]
        linhas += [(r, v, "conta") for r, v in custo]
        linhas += [("LUCRO BRUTO", lucro_bruto, "ancora"),
                   ("(-) DESPESAS OPERACIONAIS", soma(desp), "subtotal")]
        linhas += [(r, v, "conta") for r, v in desp]
        linhas += [("RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO", ebit, "ancora"),
                   ("RECEITAS FINANCEIRAS", soma(rec_fin), "subtotal")]
        linhas += [(r, v, "conta") for r, v in rec_fin]
        linhas += [("(-) DESPESAS FINANCEIRAS", soma(desp_fin), "subtotal")]
        linhas += [(r, v, "conta") for r, v in desp_fin]
        linhas += [("RESULTADO FINANCEIRO LÍQUIDO", res_fin, "ancora"),
                   ("RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO", lair, "ancora"),
                   ("(-) Imposto de renda e contribuição social correntes", ir, "conta"),
                   ("LUCRO LÍQUIDO DO EXERCÍCIO" if liquido > 0 else "PREJUÍZO DO EXERCÍCIO",
                    liquido, "ancora")]
        out[ano] = linhas
    return out


def ancoras(linhas):
    return {r: v for r, v, t in linhas if t in ("ancora", "subtotal")}


def resultado(linhas):
    return linhas[-1][1]


# ------------------------------------------------------------ DRE SERV -------
def dre_servicos(bp):
    out = {}
    for ano in ANOS:
        ant = _anterior(ano)
        if ant is None:
            dep = D.DEPRECIACAO_2023_SERV
            fin_abertura = bp[ano]["servicos"]["PNC"]["Empréstimos e Financiamentos"][0][1]
        else:
            dep = (-valor(bp[ano]["servicos"], "ANC", "Imobilizado", "(-) Depreciação")
                   + valor(bp[ant]["servicos"], "ANC", "Imobilizado", "(-) Depreciação"))
            fin_abertura = valor(bp[ant]["servicos"], "PNC", "Empréstimos e Financiamentos", "Financiamento")
        fin_fecho = valor(bp[ano]["servicos"], "PNC", "Empréstimos e Financiamentos", "Financiamento")
        rb = D.RECEITA_BRUTA_SERV[ano]
        mx = D.MIX_SERV[ano]
        ded = -round(rb * .1425)
        rl = rb + ded
        custo = -round(rl * mx["custo"])
        lb = rl + custo - dep
        adm = -round(rl * mx["adm"])
        ebit = lb + adm
        rec_mut = juros_mutuo("MUT-02/2024", ano)
        juros_fin = -int(round((fin_abertura + fin_fecho) / 2 * D.TAXA_FINAME_SERV))
        lair = ebit + rec_mut + juros_fin
        ir = -int(round(lair * D.ALIQUOTA_IR)) if lair > 0 else 0
        liq = lair + ir
        linhas = [("RECEITA BRUTA DE SERVIÇOS", rb, "ancora"),
                  ("(-) ISS, PIS e COFINS sobre serviços", ded, "conta"),
                  ("RECEITA LÍQUIDA", rl, "ancora"),
                  ("(-) Custo dos serviços prestados", custo, "conta"),
                  ("(-) Depreciação de equipamentos de montagem", -dep, "conta"),
                  ("LUCRO BRUTO", lb, "ancora"),
                  ("(-) Despesas gerais e administrativas", adm, "conta"),
                  ("RESULTADO OPERACIONAL", ebit, "ancora"),
                  ("Receitas financeiras - juros sobre mútuo com parte relacionada", rec_mut, "conta"),
                  ("(-) Despesas financeiras - juros de financiamento", juros_fin, "conta"),
                  ("RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO", lair, "ancora"),
                  ("(-) Imposto de renda e contribuição social", ir, "conta"),
                  ("LUCRO LÍQUIDO DO EXERCÍCIO" if liq > 0 else "PREJUÍZO DO EXERCÍCIO", liq, "ancora")]
        out[ano] = linhas
    return out


# ------------------------------------------------------------ DRE HOLD -------
def dre_holding(res_met, res_serv):
    """Resultado da holding = equivalência das duas controladas (100%) + juros
    do mútuo que ela concedeu − despesas próprias. A equivalência da Metalúrgica
    é o prejuízo INTEIRO mesmo depois de o investimento chegar a zero, porque o
    excedente vai para a provisão para passivo a descoberto."""
    out = {}
    for ano in ANOS:
        linhas = [
            ("Resultado de equivalência patrimonial - Piraquara Metalúrgica", res_met[ano], "conta"),
            ("Resultado de equivalência patrimonial - Piraquara Montagens", res_serv[ano], "conta"),
            ("Receita de juros sobre mútuo concedido a controlada", juros_mutuo("MUT-01/2021", ano), "conta"),
            ("(-) Despesas administrativas e honorários da administração",
             -D.DESPESAS_HOLDING[ano], "conta"),
        ]
        liq = sum(v for _, v, _t in linhas)
        linhas.append(("LUCRO LÍQUIDO DO EXERCÍCIO" if liq > 0 else "PREJUÍZO DO EXERCÍCIO", liq, "ancora"))
        out[ano] = linhas
    return out


# ------------------------------------------------------------ COVENANT -------
def covenant(bp, dre):
    """Dívida Líquida / EBITDA da Metalúrgica, com cada parcela à vista."""
    var = variacoes_met(bp)
    out = {}
    for ano in ANOS:
        a = ancoras(dre[ano])
        ebit = a["RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"]
        dep = var[ano]["depreciacao"]
        imp = var[ano]["impairment"]
        ebitda = ebit + dep + imp
        bruta = divida_bancaria(ano)
        caixa = soma(bp[ano]["metalurgica"]["AC"]["Disponível"])
        liquida = bruta - caixa
        indice = liquida / ebitda if ebitda > 0 else None
        rompido = indice is None or indice > D.COVENANT_LIMITE
        out[ano] = dict(divida_bruta=bruta, caixa=caixa, divida_liquida=liquida, ebit=ebit,
                        depreciacao=dep, impairment=imp, ebitda=ebitda,
                        indice=round(indice, 2) if indice is not None else None,
                        limite=D.COVENANT_LIMITE, rompido=rompido)
    return out


def mapa_divida(ano=2025):
    linhas = []
    for k in D.CONTRATOS:
        s = k["saldos"].get(ano)
        if s is None:
            continue
        linhas.append(dict(contrato=k["contrato"], credor=k["credor"], modalidade=k["modalidade"],
                           taxa=k["taxa"], taxa_efetiva=k["taxa_efetiva"][ano],
                           garantia=k["garantia"], covenant=k["covenant"],
                           saldo_anterior=k["saldos"].get(_anterior(ano)), saldo=s,
                           juros=juros_contrato(k, ano)))
    return linhas


# ------------------------------------------------------------- AGING ---------
FAIXAS = ["A vencer", "1 a 30 dias", "31 a 60 dias", "61 a 90 dias", "Acima de 90 dias"]

# Um fornecedor por linha, com o CÓDIGO do cadastro na frente do nome — é o
# formato medido em produção (`41518 - WELLA BRASIL LTDA.`). Não há linha de
# "demais fornecedores": o aging abre a carteira inteira, e o rótulo da linha é
# o ITEM, nunca o conceito.
FORNECEDORES = [
    # nome, peso na carteira, perfil por faixa
    ("40117 - SIDERÚRGICA SERRA AZUL S.A.", .312, [.18, .12, .10, .12, .48]),
    ("40233 - LAMINADOS PARANAPIACABA LTDA.", .141, [.36, .22, .14, .10, .18]),
    ("40361 - TUBOS E PERFIS ITAMBÉ LTDA.", .098, [.41, .19, .13, .09, .18]),
    ("40412 - TINTAS INDUSTRIAIS CAPARAÓ LTDA.", .071, [.52, .21, .11, .07, .09]),
    ("40588 - GASES TÉCNICOS PLANALTO S.A.", .063, [.47, .24, .15, .08, .06]),
    ("40602 - PARAFUSOS E FIXADORES GUAPORÉ LTDA.", .057, [.55, .20, .12, .07, .06]),
    ("40719 - ENERGIA COMERCIALIZADORA ARAUCÁRIA S.A.", .052, [.30, .25, .20, .15, .10]),
    ("40844 - TRANSPORTES RODOVIÁRIOS TIMBÓ LTDA.", .044, [.39, .23, .16, .12, .10]),
    ("40903 - MANUTENÇÃO E USINAGEM CAIAPÓ LTDA.", .036, [.62, .18, .10, .06, .04]),
    ("41027 - ELETRODOS E CONSUMÍVEIS JURUÁ LTDA.", .028, [.66, .17, .09, .05, .03]),
    ("41150 - LOCAÇÃO DE EQUIPAMENTOS TAQUARI LTDA.", .018, [.44, .20, .15, .11, .10]),
    ("90014 - STEELBRIDGE TRADING LLC (EUA)", .080, [.58, .22, .12, .08, .00]),
]

CLIENTES = [
    ("10233 - CONSTRUTORA ALTO PARAOPEBA LTDA. (EM RECUPERAÇÃO JUDICIAL)", .214, [.00, .00, .04, .06, .90]),
    ("10318 - LOGÍSTICA E ARMAZÉNS CAMPOS GERAIS S.A.", .163, [.38, .21, .14, .11, .16]),
    ("10402 - TORRES E TELECOMUNICAÇÕES MANTIQUEIRA LTDA.", .128, [.61, .19, .10, .06, .04]),
    ("10457 - AGROINDUSTRIAL VALE DO IVAÍ S.A.", .104, [.55, .22, .11, .07, .05]),
    ("10521 - CENTRO DE DISTRIBUIÇÃO ARAGUARI LTDA.", .086, [.49, .20, .14, .09, .08]),
    ("10609 - GALPÕES MODULARES SERRA DO MAR LTDA.", .072, [.30, .18, .16, .14, .22]),
    ("10688 - MINERAÇÃO PEDRA BRANCA LTDA.", .065, [.71, .16, .07, .04, .02]),
    ("10744 - PREFEITURA MUNICIPAL DE SÃO JOÃO DO OESTE", .058, [.20, .18, .17, .15, .30]),
    ("10812 - ENGENHARIA E MONTAGENS RIO PARDO LTDA.", .061, [.64, .19, .09, .05, .03]),
    ("10930 - COOPERATIVA AGRÍCOLA TRÊS FRONTEIRAS", .049, [.68, .17, .08, .04, .03]),
]


def _aging(total, carteira):
    subtotais = _reparte(total, [p for _, p, _ in carteira])
    linhas = []
    for (nome, _p, perfil), st in zip(carteira, subtotais):
        linhas.append((nome, _reparte(st, perfil), st))
    por_faixa = [sum(l[1][i] for l in linhas) for i in range(len(FAIXAS))]
    assert sum(por_faixa) == total
    return linhas, por_faixa


def aging_ap(bp, ano=2025):
    """Soma = subgrupo Fornecedores da Metalúrgica (nacionais + estrangeiros)."""
    total = soma(bp[ano]["metalurgica"]["PC"]["Fornecedores"])
    linhas, por_faixa = _aging(total, FORNECEDORES)
    return linhas, por_faixa, total


def aging_ar(bp, ano=2025):
    """Soma = duplicatas a receber BRUTAS (antes da PECLD)."""
    total = valor(bp[ano]["metalurgica"], "AC", "Contas a Receber", "Clientes")
    linhas, por_faixa = _aging(total, CLIENTES)
    return linhas, por_faixa, total


# ------------------------------------------------------------ EXTRATO --------
MESES = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto",
         "Setembro", "Outubro", "Novembro", "Dezembro"]
SAZONALIDADE = [.071, .074, .083, .086, .088, .085, .087, .090, .089, .084, .082, .081]
# Desvio do saldo de cada fim de mês contra a trajetória linear, em fração do
# saldo de abertura. Fixo (não sorteado): o extrato é determinístico.
OSCILACAO = [.42, -.18, .31, .09, -.27, .22, -.11, .36, -.34, .14, -.21, 0.0]
# Centavos que o banco tem e o balanço (em R$ mil) arredonda. Menos de R$ 500 —
# então o saldo em reais ARREDONDA para o caixa do BP, sem bater "ao centavo".
CENTAVOS_ABERTURA = 21_874      # R$ 218,74
CENTAVOS_FECHAMENTO = 31_746    # R$ 317,46


def _centavos(chave, faixa):
    h = hashlib.sha256(chave.encode("utf-8")).digest()
    return int.from_bytes(h[:4], "big") % faixa


def extrato(bp, ano=2025):
    """Extrato mensal da ÚNICA conta bancária da Metalúrgica, em CENTAVOS.

    Abertura = caixa do BP do ano anterior × 1.000; fechamento = caixa do BP
    do ano × 1.000 (mais centavos que o arredondamento para R$ mil absorve)."""
    ant = _anterior(ano)
    ini = soma(bp[ant]["metalurgica"]["AC"]["Disponível"]) * 100_000 + CENTAVOS_ABERTURA
    fim = soma(bp[ano]["metalurgica"]["AC"]["Disponível"]) * 100_000 + CENTAVOS_FECHAMENTO
    receita_cent = D.RECEITA_BRUTA_MET[ano] * 100_000
    linhas, saldo = [], ini
    for i, mes in enumerate(MESES):
        alvo = fim if i == 11 else int(ini + (fim - ini) * (i + 1) / 12 + ini * OSCILACAO[i])
        creditos = int(receita_cent * SAZONALIDADE[i] * .93) + _centavos(f"c{i}", 100_000)
        debitos = saldo + creditos - alvo
        assert debitos > 0 and alvo > 0, f"extrato {mes}: saldo {alvo} / débitos {debitos}"
        linhas.append((f"{mes}/{ano}", saldo, creditos, debitos, alvo))
        saldo = alvo
    assert saldo == fim
    assert round(fim / 100_000) == soma(bp[ano]["metalurgica"]["AC"]["Disponível"])
    return linhas, ini, fim


# ---------------------------------------------------------------- DFC --------
# Onde cada subgrupo do balanço entra na DFC. É por aqui que se prova que a DFC
# não tem rubrica de ajuste: TODA conta do balanço cai em exatamente um bloco,
# e a soma dos blocos tem de dar a variação do Disponível ao real.
OPERACIONAL_ATIVO = ("Contas a Receber", "Estoques", "Tributos a Recuperar", "Outros Créditos",
                     "Realizável a Longo Prazo")
OPERACIONAL_PASSIVO = {"PC": ("Fornecedores", "Obrigações Trabalhistas", "Obrigações Tributárias",
                              "Outras Obrigações"),
                       "PNC": ("Obrigações Tributárias",)}


def dfc_metalurgica(bp, dre, ano):
    ant = _anterior(ano)
    m, a = bp[ano]["metalurgica"], bp[ant]["metalurgica"]
    var = variacoes_met(bp)[ano]
    res = resultado(dre[ano])

    def bruto(bp_ent, sub):
        return sum(v for r, v in bp_ent["AC"].get(sub, []) + bp_ent["ANC"].get(sub, [])
                   if not r.startswith("(-)"))

    def delta_ativo(sub):
        return bruto(m, sub) - bruto(a, sub)

    def delta_passivo(secao, sub):
        return soma(m[secao].get(sub, [])) - soma(a[secao].get(sub, []))

    tm = mutuos_tabela()
    juros_cap = tm["MUT-01/2021"][ano]["juros"] + tm["MUT-02/2024"][ano]["juros"]
    captacao_mut = tm["MUT-01/2021"][ano]["captacao"] + tm["MUT-02/2024"][ano]["captacao"]

    ajustes = [
        ("Depreciação", var["depreciacao"]),
        ("Perda por redução ao valor recuperável (impairment)", var["impairment"]),
        ("Perdas estimadas em créditos de liquidação duvidosa", var["pecld"]),
        ("Provisão para perdas em estoques", var["estoques"]),
        ("Provisão para contingências", var["contingencias"]),
        ("Juros capitalizados sobre mútuos com partes relacionadas", juros_cap),
    ]
    capital_giro = [
        ("(Aumento) redução de clientes", -delta_ativo("Contas a Receber")),
        ("(Aumento) redução de estoques", -delta_ativo("Estoques")),
        ("(Aumento) redução de tributos a recuperar", -delta_ativo("Tributos a Recuperar")),
        ("(Aumento) redução de outros créditos", -delta_ativo("Outros Créditos")),
        ("(Aumento) redução de depósitos judiciais", -delta_ativo("Realizável a Longo Prazo")),
        ("Aumento (redução) de fornecedores", delta_passivo("PC", "Fornecedores")),
        ("Aumento (redução) de obrigações trabalhistas", delta_passivo("PC", "Obrigações Trabalhistas")),
        ("Aumento (redução) de obrigações tributárias e parcelamentos",
         delta_passivo("PC", "Obrigações Tributárias") + delta_passivo("PNC", "Obrigações Tributárias")),
        ("Aumento (redução) de adiantamentos de clientes", delta_passivo("PC", "Outras Obrigações")),
    ]
    fco = res + soma(ajustes) + soma(capital_giro)
    fci = -delta_ativo("Imobilizado")
    emp = divida_bancaria(ano) - divida_bancaria(ant)
    fcf = emp + captacao_mut
    dcaixa = soma(m["AC"]["Disponível"]) - soma(a["AC"]["Disponível"])
    assert fco + fci + fcf == dcaixa, f"DFC {ano} não fecha no caixa: {fco + fci + fcf} != {dcaixa}"

    linhas = [("FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS", None, "ancora"),
              ("Lucro (prejuízo) do exercício", res, "conta"),
              ("Ajustes por itens que não afetam o caixa:", None, "subtotal")]
    linhas += [(r, v, "conta") for r, v in ajustes]
    linhas += [("Variações no capital de giro:", None, "subtotal")]
    linhas += [(r, v, "conta") for r, v in capital_giro]
    linhas += [("Caixa líquido gerado (consumido) pelas atividades operacionais", fco, "subtotal"),
               ("FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO", None, "ancora"),
               ("Aquisições de imobilizado", fci, "conta"),
               ("Caixa líquido consumido pelas atividades de investimento", fci, "subtotal"),
               ("FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO", None, "ancora"),
               ("Captações (amortizações) líquidas de empréstimos bancários", emp, "conta"),
               ("Captação de mútuos com partes relacionadas", captacao_mut, "conta"),
               ("Caixa líquido gerado pelas atividades de financiamento", fcf, "subtotal"),
               ("AUMENTO (REDUÇÃO) LÍQUIDO DE CAIXA", dcaixa, "ancora"),
               ("Caixa no início do exercício", soma(a["AC"]["Disponível"]), "conta"),
               ("Caixa no fim do exercício", soma(m["AC"]["Disponível"]), "ancora")]
    return linhas, dict(fco=fco, fci=fci, fcf=fcf, variacao=dcaixa,
                        caixa_inicial=soma(a["AC"]["Disponível"]),
                        caixa_final=soma(m["AC"]["Disponível"]))
