# -*- coding: utf-8 -*-
"""Demonstrações e anexos do book CANASTRA, TODOS amarrados ao balanço.

A regra desta camada é uma só: **nenhum documento digita um total que já existe
no balanço**. A despesa de depreciação sai da variação da depreciação acumulada;
a PECLD sai da variação da provisão; o total do mapa de dívida é a soma das
contas de empréstimo; o aging soma as duplicatas; a situação fiscal soma os
parcelamentos. É isso que faz o book ser um TESTE e não um conjunto de PDFs
bonitos: se um número deixar de bater, o `assert` derruba a geração antes de
alguém rodar a extração sobre um insumo mentiroso.

Onde há divergência, ela é DELIBERADA, está no gabarito e no guia, e existe para
o sistema ter o que encontrar (a planilha de mútuos, e só ela).
"""

import dados as D
import motor as M

ANOS = D.ANOS

# Receita bruta da Indústria por exercício (R$ mil). É a única série "de fora"
# do balanço, porque receita não é saldo — e é dela que o faturamento mensal, as
# deduções e o CMV descem.
RECEITA_BRUTA = {2023: 318_000, 2024: 246_000, 2025: 188_000}

# Câmbio de fechamento usado na tranche em dólar do mapa de dívida.
CAMBIO_FECHAMENTO = {2023: 4.8413, 2024: 6.1923, 2025: 5.4408}


# ---------------------------------------------------------------------------
# Leituras do balanço (é daqui que a DRE tira o que não pode inventar).
# ---------------------------------------------------------------------------
def _conta(bp, ano, ent, secao, sub, prefixo):
    return M.valor_conta(bp[ano][ent], secao, sub, prefixo)


def variacoes(bp, tot, ent="industria"):
    """Movimentos do exercício LIDOS do balanço — depreciação, PECLD, provisões,
    obsolescência, diferido. Cada um vira uma linha de despesa da DRE, e é isso
    que faz DRE e balanço contarem a mesma história."""
    v = {}
    for ano in ANOS[1:]:
        ant = ANOS[ANOS.index(ano) - 1]
        dep = (-_conta(bp, ano, ent, "ANC", "Imobilizado", "(-) Depreciação acumulada")
               + _conta(bp, ant, ent, "ANC", "Imobilizado", "(-) Depreciação acumulada"))
        amort_du = (-_conta(bp, ano, ent, "ANC", "Imobilizado", "(-) Amortização acumulada do direito de uso")
                    + _conta(bp, ant, ent, "ANC", "Imobilizado", "(-) Amortização acumulada do direito de uso"))
        amort_int = (-_conta(bp, ano, ent, "ANC", "Intangível", "(-) Amortização acumulada")
                     + _conta(bp, ant, ent, "ANC", "Intangível", "(-) Amortização acumulada"))
        pecld = (-_conta(bp, ano, ent, "AC", "Contas a Receber", "(-) Perdas estimadas")
                 + _conta(bp, ant, ent, "AC", "Contas a Receber", "(-) Perdas estimadas"))
        obsol = (-_conta(bp, ano, ent, "AC", "Estoques", "(-) Provisão para obsolescência")
                 + _conta(bp, ant, ent, "AC", "Estoques", "(-) Provisão para obsolescência"))
        prov = (M.soma_folhas({"x": bp[ano][ent]["PNC"].get("Provisões", [])})
                - M.soma_folhas({"x": bp[ant][ent]["PNC"].get("Provisões", [])}))
        difer = (_conta(bp, ano, ent, "ANC", "Realizável a Longo Prazo", "Tributos diferidos ativos")
                 - _conta(bp, ant, ent, "ANC", "Realizável a Longo Prazo", "Tributos diferidos ativos"))
        v[ano] = {"depreciacao": dep, "amort_du": amort_du, "amort_intangivel": amort_int,
                  "pecld": pecld, "obsolescencia": obsol, "provisoes": prov, "ir_diferido": difer,
                  "dea_total": dep + amort_du + amort_int}
    # 2023 não tem exercício anterior no book: a movimentação é DECLARADA pela
    # nota explicativa, não medida. Fica explícito para ninguém confundir
    # "medido no balanço" com "afirmado pela empresa".
    v[2023] = {"depreciacao": 5_900, "amort_du": 0, "amort_intangivel": 480,
               "pecld": 640, "obsolescencia": 210, "provisoes": 900, "ir_diferido": 0,
               "dea_total": 6_380}
    return v


def divida_bancaria(bp, ano, ent="industria"):
    """Toda a dívida onerosa da entidade, curto + longo. É o total que o mapa de
    dívida tem de reproduzir (em REAIS, outra escala)."""
    pc = M.soma_folhas({"x": bp[ano][ent]["PC"].get("Empréstimos e Financiamentos",
                                                    bp[ano][ent]["PC"].get("Empréstimos", []))})
    pnc = M.soma_folhas({"x": bp[ano][ent]["PNC"].get("Empréstimos e Financiamentos",
                                                      bp[ano][ent]["PNC"].get("Empréstimos", []))})
    return pc + pnc


# ---------------------------------------------------------------------------
# DRE da Indústria — três exercícios, cascata completa.
#
# O resultado de cada ano NÃO é escolhido: é a variação do PL do próprio balanço
# (que é o que resultado significa quando não há aporte nem distribuição). Uma
# linha — "Outras receitas (despesas) operacionais líquidas" — absorve a
# diferença entre a cascata montada e esse resultado, exatamente como a conta de
# "outras" absorve na contabilidade de verdade.
# ---------------------------------------------------------------------------
DIVIDENDOS_2023 = 2_400
LUCRO_2023 = 14_800


def resultado_alvo(tot, ent="industria"):
    """O que a DRE de cada exercício TEM de dar."""
    alvo = {2023: LUCRO_2023}
    for ano in ANOS[1:]:
        ant = ANOS[ANOS.index(ano) - 1]
        alvo[ano] = tot[ano][ent]["PL"] - tot[ant][ent]["PL"]
    return alvo


def dre_industria(bp, tot):
    """Devolve {ano: [(rótulo, valor, tipo)]}, com tipo em
    conta | subtotal | ancora. Valores de despesa vêm NEGATIVOS — é como o PDF
    os imprime (entre parênteses) e como a extração os entrega."""
    var = variacoes(bp, tot)
    alvo = resultado_alvo(tot)
    juros = juros_por_ano(bp)
    out = {}

    # Participação de cada linha na receita, por exercício. A margem comprime:
    # matéria-prima sobe de 60% para 71% da receita líquida em dois anos, que é
    # a história do papel kraft encarecendo enquanto o preço de venda não sobe.
    mix = {
        2023: dict(mp=.545, mod=.112, energia=.040, outros=.031, vendas=.058, ga=.048),
        2024: dict(mp=.680, mod=.130, energia=.046, outros=.034, vendas=.061, ga=.056),
        2025: dict(mp=.710, mod=.143, energia=.052, outros=.037, vendas=.064, ga=.060),
    }
    honorarios = {2023: 1_800, 2024: 1_900, 2025: 2_100}
    impairment = {2023: 0, 2024: -9_800, 2025: 0}
    reestruturacao = {2023: 0, 2024: 0, 2025: -4_200}
    rec_fin = {2023: 1_100, 2024: 420, 2025: 90}
    cambio = {2023: 380, 2024: -1_200, 2025: -2_100}
    encargo_transacao = {2023: 0, 2024: 0, 2025: -3_900}
    ir_corrente = {2023: -5_100, 2024: 0, 2025: 0}

    for ano in ANOS:
        rb = RECEITA_BRUTA[ano]
        m = mix[ano]
        icms, pis, dev = -round(rb * .170), -round(rb * .074), -round(rb * .012)
        rl = rb + icms + pis + dev

        cmv = [
            ("(-) Matérias-primas e insumos consumidos", -round(rl * m["mp"])),
            ("(-) Mão de obra direta e encargos sociais", -round(rl * m["mod"])),
            ("(-) Energia elétrica, gás e utilidades industriais", -round(rl * m["energia"])),
            ("(-) Depreciação de máquinas e instalações industriais",
             -round(var[ano]["depreciacao"] * .82)),
            ("(-) Outros custos de produção", -round(rl * m["outros"])),
        ]
        total_cmv = sum(v for _, v in cmv)
        lucro_bruto = rl + total_cmv

        desp = [
            ("(-) Despesas com vendas, fretes e comissões", -round(rl * m["vendas"])),
            ("(-) Despesas gerais e administrativas", -round(rl * m["ga"])),
            ("(-) Honorários da administração", -honorarios[ano]),
            ("(-) Perdas estimadas em créditos de liquidação duvidosa", -var[ano]["pecld"]),
            ("(-) Provisão para obsolescência de estoques", -var[ano]["obsolescencia"]),
            ("(-) Provisão para contingências trabalhistas, tributárias e cíveis",
             -var[ano]["provisoes"]),
            ("(-) Depreciação e amortização administrativa",
             -(var[ano]["dea_total"] - round(var[ano]["depreciacao"] * .82))),
        ]
        if impairment[ano]:
            desp.append(("(-) Perda por redução ao valor recuperável de ativos (impairment)",
                         impairment[ano]))
        if reestruturacao[ano]:
            desp.append(("(-) Despesas de reestruturação, rescisões e assessores",
                         reestruturacao[ano]))

        financeiro = [
            ("Receitas financeiras", rec_fin[ano]),
            ("(-) Despesas financeiras", -juros[ano]),
        ]
        if encargo_transacao[ano]:
            financeiro.append(("(-) Multas e juros reconhecidos na adesão à transação tributária",
                               encargo_transacao[ano]))
        financeiro.append(("Variações cambiais líquidas", cambio[ano]))

        tributos = [("(-) Imposto de renda e contribuição social correntes", ir_corrente[ano])]
        if var[ano]["ir_diferido"]:
            tributos.append(("Imposto de renda e contribuição social diferidos",
                             var[ano]["ir_diferido"]))

        # A linha que fecha. Ela existe na contabilidade de verdade e aqui tem a
        # mesma função: absorver o que as linhas nomeadas não explicam.
        fixo = (lucro_bruto + sum(v for _, v in desp) + sum(v for _, v in financeiro)
                + sum(v for _, v in tributos))
        outras = alvo[ano] - fixo
        desp.append(("Outras receitas (despesas) operacionais, líquidas", outras))

        ebit = lucro_bruto + sum(v for _, v in desp)
        res_fin = sum(v for _, v in financeiro)
        antes = ebit + res_fin
        liquido = antes + sum(v for _, v in tributos)
        assert liquido == alvo[ano], f"DRE {ano} não fechou no PL: {liquido} != {alvo[ano]}"

        linhas = [("RECEITA OPERACIONAL BRUTA", rb, "ancora")]
        linhas += [
            ("Vendas de embalagens - mercado interno", round(rb * .78), "conta"),
            ("Vendas de embalagens - mercado externo", round(rb * .12), "conta"),
            ("Prestação de serviços de conversão e corte", round(rb * .06), "conta"),
            ("Vendas para empresas do grupo (Canastra Comercial)",
             rb - round(rb * .78) - round(rb * .12) - round(rb * .06), "conta"),
        ]
        linhas += [("(-) DEDUÇÕES DA RECEITA BRUTA", icms + pis + dev, "subtotal"),
                   ("(-) ICMS sobre vendas", icms, "conta"),
                   ("(-) PIS e COFINS sobre vendas", pis, "conta"),
                   ("(-) Devoluções, descontos e abatimentos", dev, "conta"),
                   ("RECEITA OPERACIONAL LÍQUIDA", rl, "ancora"),
                   ("(-) CUSTO DOS PRODUTOS VENDIDOS E DOS SERVIÇOS PRESTADOS", total_cmv, "subtotal")]
        linhas += [(r, v, "conta") for r, v in cmv]
        linhas += [("LUCRO BRUTO", lucro_bruto, "ancora"),
                   ("(-) DESPESAS OPERACIONAIS", sum(v for _, v in desp), "subtotal")]
        linhas += [(r, v, "conta") for r, v in desp]
        linhas += [("RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO", ebit, "ancora"),
                   ("RESULTADO FINANCEIRO LÍQUIDO", res_fin, "subtotal")]
        linhas += [(r, v, "conta") for r, v in financeiro]
        linhas += [("RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO", antes, "ancora")]
        linhas += [(r, v, "conta") for r, v in tributos]
        rotulo_final = "LUCRO LÍQUIDO DO EXERCÍCIO" if liquido > 0 else "PREJUÍZO DO EXERCÍCIO"
        linhas += [(rotulo_final, liquido, "ancora")]
        out[ano] = linhas
    return out


def ancoras(linhas):
    return {r: v for r, v, t in linhas if t in ("ancora", "subtotal")}


# ---------------------------------------------------------------------------
# MAPA DE DÍVIDA — em REAIS (unidades), enquanto o balanço está em R$ mil.
#
# Duas armadilhas de propósito: a escala (o total é 1.000× o do balanço) e a
# tranche em DÓLAR, que traz o saldo em US$ numa coluna e o equivalente em R$ na
# outra — somar a coluna errada erra por ~5,4×.
# ---------------------------------------------------------------------------
CONTRATOS = [
    # (banco, modalidade, nº contrato, garantia, taxa, peso, situação)
    ("Banco Meridional S.A.", "Capital de giro", "CG-2021-884.117", "Aval dos sócios + recebíveis",
     "CDI + 4,80% a.a.", 0.20, "Vencido - cláusula restritiva descumprida"),
    ("Banco Meridional S.A.", "Capital de giro", "CG-2022-901.554", "Aval dos sócios",
     "CDI + 5,20% a.a.", 0.14, "Vencido - cláusula restritiva descumprida"),
    ("Banco Praia Grande S.A.", "Capital de giro", "CG-2023-114.902", "Alienação de máquinas",
     "CDI + 6,10% a.a.", 0.11, "Adimplente"),
    ("Banco Praia Grande S.A.", "Conta garantida", "CC-2024-772.318", "Aval dos sócios",
     "CDI + 8,90% a.a.", 0.05, "Adimplente"),
    ("Banco de Fomento Nacional", "FINAME - linha de conversão", "FIN-2019-336.070",
     "Alienação fiduciária do bem", "TLP + 3,10% a.a.", 0.09, "Adimplente"),
    ("Banco de Fomento Nacional", "FINAME - empilhadeiras", "FIN-2020-338.221",
     "Alienação fiduciária do bem", "TLP + 2,90% a.a.", 0.03, "Adimplente"),
    ("Banco Serra Norte S.A.", "Antecipação de recebíveis", "ANT-2025-556.114",
     "Cessão fiduciária de duplicatas", "2,45% a.m.", 0.13, "Adimplente"),
    ("Banco Serra Norte S.A.", "Capital de giro", "CG-2024-221.907", "Aval dos sócios",
     "CDI + 7,40% a.a.", 0.08, "Renegociado em 2025"),
    ("Financeira Cruzeiro S.A.", "Desconto de duplicatas", "DD-2025-118.443",
     "Coobrigação", "3,10% a.m.", 0.07, "Adimplente"),
    ("Banco Atlântico Sul S.A.", "Capital de giro", "CG-2022-447.001", "Aval dos sócios",
     "CDI + 5,90% a.a.", 0.06, "Adimplente"),
    # A tranche em MOEDA ESTRANGEIRA. `usd` marca a linha; o saldo em reais é o
    # equivalente convertido pelo câmbio de fechamento.
    ("Banco Atlântico Sul S.A. (NY Branch)", "Pré-pagamento de exportação (ACC)",
     "ACC-2024-090.771", "Penhor de recebíveis de exportação", "SOFR + 5,25% a.a.", 0.04,
     "Adimplente|usd"),
]


def juros_por_ano(bp):
    """Despesa financeira do exercício, calculada sobre o saldo MÉDIO da dívida
    do próprio balanço. Não é número escolhido: é o que o mapa de dívida vai
    reproduzir contrato a contrato."""
    taxa = {2023: 0.181, 2024: 0.223, 2025: 0.268}  # custo médio efetivo crescente
    j = {}
    for ano in ANOS:
        ant = ANOS[ANOS.index(ano) - 1] if ano != ANOS[0] else ano
        medio = (divida_bancaria(bp, ano) + divida_bancaria(bp, ant)) / 2
        j[ano] = int(round(medio * taxa[ano]))
    return j


def mapa_divida(bp, ano=2025):
    """Contratos em REAIS (unidades). A soma dos saldos reproduz a dívida
    bancária do balanço; a soma dos juros reproduz a despesa financeira da DRE."""
    total_mil = divida_bancaria(bp, ano)
    juros_mil = juros_por_ano(bp)[ano]
    total = total_mil * 1000
    juros_total = juros_mil * 1000
    cambio = CAMBIO_FECHAMENTO[ano]

    linhas, acumulado, acum_juros = [], 0, 0
    for i, (banco, modalidade, contrato, garantia, taxa, peso, situacao) in enumerate(CONTRATOS):
        ultimo = i == len(CONTRATOS) - 1
        saldo = total - acumulado if ultimo else int(round(total * peso))
        j = juros_total - acum_juros if ultimo else int(round(juros_total * peso))
        acumulado += saldo
        acum_juros += j
        usd = "|usd" in situacao
        linhas.append({
            "banco": banco, "modalidade": modalidade, "contrato": contrato,
            "garantia": garantia, "taxa": taxa, "situacao": situacao.replace("|usd", ""),
            "saldo": saldo, "juros": j,
            "saldo_usd": round(saldo / cambio, 2) if usd else None,
            "vencimento": VENCIMENTOS[i % len(VENCIMENTOS)],
        })
    assert sum(x["saldo"] for x in linhas) == total, "mapa de dívida não bate com o balanço"
    assert sum(x["juros"] for x in linhas) == juros_total, "juros do mapa não batem com a DRE"
    return linhas, total, juros_total


VENCIMENTOS = ["15/03/2026", "20/07/2026", "10/11/2027", "05/02/2026", "28/09/2029",
               "12/06/2028", "30/01/2026", "22/04/2027", "18/08/2026", "07/12/2026",
               "25/05/2027"]


# ---------------------------------------------------------------------------
# FATURAMENTO — 36 meses (jan/2023 a dez/2025), em REAIS (unidades).
#
# Três estresses: a série é MENSAL e tem de sair cronológica (não alfabética); a
# escala é diferente da DRE (reais × R$ mil); e há linhas NÃO MONETÁRIAS
# (ticket médio, pedidos, clientes ativos) que não podem herdar a escala.
# ---------------------------------------------------------------------------
MESES = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
         "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]

# Sazonalidade da embalagem: pico no 4º trimestre (safra e Natal), vale em
# janeiro/fevereiro. Soma 12,000 por construção.
SAZONALIDADE = [0.071, 0.068, 0.082, 0.079, 0.084, 0.086,
                0.088, 0.090, 0.086, 0.092, 0.094, 0.080]


def faturamento_36m():
    """Devolve [(ano, mês, faturamento_R$, pedidos, ticket_médio_R$)] e os
    totais por ano — que reproduzem a RECEITA BRUTA da DRE, em reais."""
    linhas, totais = [], {}
    for ano in ANOS:
        bruta = RECEITA_BRUTA[ano] * 1000
        acumulado = 0
        for i, mes in enumerate(MESES):
            ultimo = i == 11
            v = bruta - acumulado if ultimo else int(round(bruta * SAZONALIDADE[i]))
            acumulado += v
            pedidos = max(40, int(round(v / (14_800 + 260 * i))))
            linhas.append((ano, mes, v, pedidos, round(v / pedidos, 2)))
        totais[ano] = acumulado
        assert acumulado == bruta, f"faturamento {ano} não bate com a receita bruta"
    return linhas, totais


def faturamento_intragrupo(bp):
    """Quem fatura para quem, dentro do grupo. Os totais são os mesmos saldos
    que o combinado elimina — outra vez, nada digitado."""
    linhas = []
    for ano in ANOS:
        agro = M.valor_conta(bp[ano]["agro"], "AC", "Contas a Receber", "Contas a receber intragrupo")
        ind = M.valor_conta(bp[ano]["comercial"], "PC", "Fornecedores", "Fornecedores intragrupo")
        alug = M.valor_conta(bp[ano]["imob"], "AC", "Contas a Receber", "Aluguéis a receber - Canastra Indústria")
        frete = M.valor_conta(bp[ano]["transportes"], "AC", "Contas a Receber", "Conta corrente a receber")
        linhas.append((ano, [
            ("Canastra Agroflorestal", "Canastra Indústria", "Madeira e resíduos", agro),
            ("Canastra Indústria", "Canastra Comercial", "Embalagens para revenda", ind),
            ("Canastra Imobiliária SPE", "Canastra Indústria", "Aluguel de galpões", alug),
            ("CN Transportes", "Canastra Indústria", "Fretes e logística", frete),
        ]))
    return linhas


# ---------------------------------------------------------------------------
# MÚTUOS INTRAGRUPO — com a ÚNICA divergência deliberada do book.
# ---------------------------------------------------------------------------
DIVERGENCIA_MUTUOS = 240  # R$ mil a MENOS na planilha do que no balanço


def mutuos(bp, tot, ano=2025):
    saldos = []
    for k in D.CONTROLADAS:
        v = M.valor_conta(bp[ano][k], "PC", "Partes Relacionadas", "Mútuos a pagar")
        if v:
            saldos.append((D.ENTIDADES["holding"]["razao_social"],
                           D.ENTIDADES[k]["razao_social"], v))
    total_balanco = tot[ano]["_mutuos_holding"]
    assert sum(v for _, _, v in saldos) == total_balanco
    # A planilha do controller "esqueceu" um aditivo — é o que o sistema tem de
    # mostrar para um humano, não corrigir sozinho.
    saldos_planilha = [(a, b, v - DIVERGENCIA_MUTUOS if i == 0 else v)
                       for i, (a, b, v) in enumerate(saldos)]
    return saldos_planilha, sum(v for _, _, v in saldos_planilha), total_balanco


# ---------------------------------------------------------------------------
# AGING de recebíveis e de pagáveis. Os totais são os saldos BRUTOS do balanço.
# ---------------------------------------------------------------------------
FAIXAS_AR = ["A vencer", "1 a 30 dias", "31 a 60 dias", "61 a 90 dias",
             "91 a 180 dias", "Acima de 180 dias"]
PERFIL_AR = {2023: [.72, .12, .07, .04, .03, .02],
             2024: [.58, .14, .09, .07, .07, .05],
             2025: [.41, .13, .10, .09, .14, .13]}

CLIENTES = [
    "Alimentos Serra Dourada S.A.", "Bebidas Vale do Rio Ltda.", "Frigorífico Boa Safra S.A.",
    "Distribuidora Campo Verde Ltda.", "Indústria de Laticínios Pontal S.A.",
    "Hortifruti Exportação Sul Ltda.", "Química Ipê Ltda.", "Cerâmica Monte Belo Ltda.",
    "Papelaria Central Distribuidora", "Agro Sementes Planalto S.A.",
    "Cooperativa Agroindustrial Canastra", "Demais clientes (312 sacados)",
]
PESO_CLIENTE = [.19, .14, .11, .09, .08, .07, .06, .05, .04, .04, .03, .10]


def aging_recebiveis(bp, ano=2025):
    """Por cliente × faixa de vencimento. Soma = duplicatas a receber BRUTAS
    (interno + externo), antes da PECLD e antes da antecipação."""
    interno = M.valor_conta(bp[ano]["industria"], "AC", "Contas a Receber", "Clientes - duplicatas") \
        or M.valor_conta(bp[ano]["industria"], "AC", "Contas a Receber", "Duplicatas a receber de clientes - mercado interno")
    externo = M.valor_conta(bp[ano]["industria"], "AC", "Contas a Receber",
                            "Duplicatas a receber de clientes - mercado externo")
    total = interno + externo
    perfil = PERFIL_AR[ano]

    linhas, acum_cli = [], 0
    for i, cliente in enumerate(CLIENTES):
        ultimo = i == len(CLIENTES) - 1
        st = total - acum_cli if ultimo else int(round(total * PESO_CLIENTE[i]))
        acum_cli += st
        faixas, acum_f = [], 0
        for jx, p in enumerate(perfil):
            uf = jx == len(perfil) - 1
            v = st - acum_f if uf else int(round(st * p))
            acum_f += v
            faixas.append(v)
        linhas.append((cliente, faixas, st))
    assert sum(x[2] for x in linhas) == total, "aging AR não bate com o balanço"
    vencido = sum(sum(f[1:]) for _, f, _ in linhas)
    return linhas, total, vencido


FAIXAS_AP = ["A vencer", "1 a 30 dias", "31 a 60 dias", "61 a 90 dias", "Acima de 90 dias"]
PERFIL_AP = {2023: [.86, .08, .03, .02, .01],
             2024: [.71, .13, .07, .05, .04],
             2025: [.48, .17, .12, .10, .13]}
FORNECEDORES = [
    "Papéis e Celulose Aracati S.A.", "Tintas e Adesivos Ipiranga Ltda.",
    "Energia Distribuidora do Sudeste S.A.", "Transportadora Rota Norte Ltda.",
    "Ferramentas e Peças Industriais Vega Ltda.", "Aparas e Reciclagem Bom Retiro Ltda.",
    "Manutenção Industrial Delta Ltda.", "Demais fornecedores (184 credores)",
]
PESO_FORN = [.31, .14, .12, .09, .08, .07, .05, .14]


def aging_pagaveis(bp, ano=2025):
    """Por fornecedor × faixa. Soma = fornecedores do balanço (nacionais +
    estrangeiros + títulos vencidos), SEM o intragrupo — que é eliminado no
    combinado e por isso aparece em documento próprio."""
    pc = bp[ano]["industria"]["PC"]["Fornecedores"]
    total = sum(v for rot, v in pc if not rot.startswith("Fornecedores intragrupo"))
    perfil = PERFIL_AP[ano]
    linhas, acum = [], 0
    for i, forn in enumerate(FORNECEDORES):
        ultimo = i == len(FORNECEDORES) - 1
        st = total - acum if ultimo else int(round(total * PESO_FORN[i]))
        acum += st
        faixas, af = [], 0
        for jx, p in enumerate(perfil):
            uf = jx == len(perfil) - 1
            v = st - af if uf else int(round(st * p))
            af += v
            faixas.append(v)
        linhas.append((forn, faixas, st))
    assert sum(x[2] for x in linhas) == total, "aging AP não bate com o balanço"
    return linhas, total, sum(sum(f[1:]) for _, f, _ in linhas)


# ---------------------------------------------------------------------------
# ESTOQUES — com QUANTIDADE e preço unitário ao lado do valor. As colunas de
# quantidade (t, milheiro, unidade) NÃO são dinheiro, e é isso que se testa.
# ---------------------------------------------------------------------------
ITENS_ESTOQUE = [
    ("Matérias-primas - papel kraft e aparas", [
        ("Bobina kraft 180 g/m² - fornecedor nacional", "t", 1_240),
        ("Bobina kraft 250 g/m² - fornecedor nacional", "t", 860),
        ("Aparas classificadas tipo II", "t", 2_180),
        ("Amido e adesivos industriais", "t", 96),
    ]),
    ("Produtos em elaboração", [
        ("Chapas onduladas em processo", "milheiro", 412),
        ("Caixas em processo de impressão", "milheiro", 268),
    ]),
    ("Produtos acabados", [
        ("Caixa de papelão ondulado - linha alimentos", "milheiro", 1_180),
        ("Caixa de papelão ondulado - linha hortifruti", "milheiro", 940),
        ("Chapa avulsa - venda direta", "milheiro", 320),
    ]),
    ("Materiais de embalagem, manutenção e consumo", [
        ("Peças de reposição e rolamentos", "unidade", 3_860),
        ("Materiais de consumo geral", "unidade", 12_400),
    ]),
]


def estoques(bp, ano=2025):
    """Cada grupo soma exatamente a conta de estoque do balanço; a provisão para
    obsolescência aparece como linha redutora, igual ao balanço."""
    est = {rot: v for rot, v in bp[ano]["industria"]["AC"]["Estoques"]}
    grupos = []
    for grupo, itens in ITENS_ESTOQUE:
        if grupo not in est:
            continue
        total_grupo = est[grupo]
        pesos = [q for _, _, q in itens]
        soma_pesos = sum(pesos)
        linhas, acum = [], 0
        for i, (item, unidade, qtd) in enumerate(itens):
            ultimo = i == len(itens) - 1
            v = total_grupo - acum if ultimo else int(round(total_grupo * qtd / soma_pesos))
            acum += v
            linhas.append((item, unidade, qtd, v, round(v * 1000 / qtd, 2)))
        assert sum(x[3] for x in linhas) == total_grupo
        grupos.append((grupo, linhas, total_grupo))
    # Conta de estoque que não tem abertura por item (importação em trânsito, por
    # exemplo) entra como grupo de uma linha só. Ignorá-la faria o documento não
    # somar o balanço no exercício em que ela existe — e ela existe só em dois
    # dos três, que é justamente o caso difícil.
    cobertas = {g[0] for g in grupos}
    for rot, v in est.items():
        if rot.startswith("(-)") or rot in cobertas:
            continue
        grupos.append((rot, [(rot, "-", 0, v, None)], v))
    provisao = est.get("(-) Provisão para obsolescência de estoques", 0)
    total = sum(g[2] for g in grupos) + provisao
    assert total == M.soma_folhas({"x": bp[ano]["industria"]["AC"]["Estoques"]})
    return grupos, provisao, total


# ---------------------------------------------------------------------------
# SITUAÇÃO FISCAL — parcelamentos e tributos correntes.
#
# É o documento que alimenta a aba de tributos do modelo. A distinção que ele
# publica (parcelamento × tributo corrente × provisão) é exatamente a que o
# motor precisa para não girar o acordo com a Receita contra a receita.
# ---------------------------------------------------------------------------
def situacao_fiscal(bp, ano=2025):
    ind = bp[ano]["industria"]
    com = bp[ano]["comercial"]
    cp = {r: v for r, v in ind["PC"].get("Obrigações Tributárias", [])}
    lp = {r: v for r, v in ind["PNC"].get("Obrigações Tributárias", [])}
    cp_com = {r: v for r, v in com["PC"].get("Obrigações Tributárias", [])}

    transacao_cp = cp.get("Parcelamento - transação tributária federal (curto prazo)", 0)
    transacao_lp = lp.get("Parcelamento - transação tributária federal (longo prazo)", 0)
    refis = lp.get("REFIS - saldo remanescente", 0)
    icms_com = cp_com.get("Parcelamento de ICMS estadual", 0)

    parcelamentos = [
        {"entidade": "CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.",
         "programa": "Transação tributária federal (Lei 13.988/2020) - adesão em 14/04/2025",
         "tributos": "IRPJ, CSLL, PIS, COFINS e contribuições previdenciárias",
         "saldo_cp": transacao_cp, "saldo_lp": transacao_lp,
         "parcelas_total": 60, "parcelas_pagas": 8, "situacao": "Em dia"},
        {"entidade": "CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.",
         "programa": "REFIS estadual - Programa de Regularização de ICMS (2019)",
         "tributos": "ICMS e multas de ofício",
         "saldo_cp": 0, "saldo_lp": refis,
         "parcelas_total": 120, "parcelas_pagas": 79, "situacao": "Em dia"},
        {"entidade": "CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.",
         "programa": "Parcelamento ordinário de ICMS - SEFAZ",
         "tributos": "ICMS declarado e não recolhido",
         "saldo_cp": icms_com, "saldo_lp": 0,
         "parcelas_total": 36, "parcelas_pagas": 11, "situacao": "Em atraso (2 parcelas)"},
    ]
    correntes = [(r, v) for r, v in cp.items() if not r.startswith("Parcelamento")]
    provisoes = [(r, v) for r, v in ind["PNC"].get("Provisões", [])
                 if "tributár" in r.lower()]

    total_parcelamentos = sum(p["saldo_cp"] + p["saldo_lp"] for p in parcelamentos)
    total_correntes = sum(v for _, v in correntes)
    return parcelamentos, correntes, provisoes, total_parcelamentos, total_correntes


# ---------------------------------------------------------------------------
# CONTINGÊNCIAS — por prognóstico. Só PROVÁVEL está provisionado no balanço;
# possível e remoto são divulgação. Somar os três é o erro clássico.
# ---------------------------------------------------------------------------
PROCESSOS = [
    ("Trabalhista", "Reclamações de horas extras e adicional de insalubridade (34 processos)", "Provável"),
    ("Trabalhista", "Reconhecimento de vínculo - motoristas agregados (6 processos)", "Possível"),
    ("Tributária", "Glosa de créditos de ICMS sobre energia elétrica - autos de infração", "Provável"),
    ("Tributária", "Exclusão do ICMS da base do PIS/COFINS - pedido de restituição", "Remoto"),
    ("Cível", "Ação indenizatória por rescisão de contrato de fornecimento", "Provável"),
    ("Cível", "Execuções de fornecedores por títulos vencidos (11 ações)", "Possível"),
    ("Ambiental", "Auto de infração - destinação de resíduos industriais", "Possível"),
]


def contingencias(bp, ano=2025):
    """O provisionado sai do balanço; possível e remoto são valores de risco
    divulgados (e nunca somados ao passivo)."""
    prov = {r: v for r, v in bp[ano]["industria"]["PNC"].get("Provisões", [])}
    provisionado = {
        "Trabalhista": prov.get("Provisão para contingências trabalhistas", 0),
        "Tributária": prov.get("Provisão para contingências tributárias", 0),
        "Cível": prov.get("Provisão para contingências cíveis", 0),
        "Ambiental": 0,
    }
    risco_possivel = {"Trabalhista": 3_180, "Tributária": 0, "Cível": 7_420, "Ambiental": 1_960}
    risco_remoto = {"Trabalhista": 0, "Tributária": 12_800, "Cível": 0, "Ambiental": 0}

    linhas = []
    for natureza, descricao, prognostico in PROCESSOS:
        if prognostico == "Provável":
            valor, provisionado_v = provisionado[natureza], provisionado[natureza]
        elif prognostico == "Possível":
            valor, provisionado_v = risco_possivel[natureza], 0
        else:
            valor, provisionado_v = risco_remoto[natureza], 0
        linhas.append((natureza, descricao, prognostico, valor, provisionado_v))
    total_provisionado = sum(x[4] for x in linhas)
    assert total_provisionado == sum(provisionado.values()), "contingências não batem com o balanço"
    return linhas, total_provisionado, sum(risco_possivel.values()), sum(risco_remoto.values())


# ---------------------------------------------------------------------------
# IMOBILIZADO — custo, depreciação acumulada e TAXA anual por classe.
# A taxa é a "vida útil por classe" que o Kit Básico não coleta; aqui ela existe
# no documento, e é ela que o modelo pode medir em vez de arbitrar.
# ---------------------------------------------------------------------------
TAXAS = {
    "Terrenos": 0.0,
    "Edificações e benfeitorias": 4.0,
    "Máquinas, aparelhos e equipamentos industriais": 10.0,
    "Instalações industriais": 10.0,
    "Veículos e empilhadeiras": 20.0,
    "Móveis e utensílios": 10.0,
    "Imobilizado em andamento - linha de conversão de chapas": 0.0,
    "Direito de uso - arrendamentos": 20.0,
}


def imobilizado(bp, ano=2025):
    """Custo por classe (do balanço), taxa anual e a depreciação acumulada
    RATEADA pelas classes depreciáveis — o rateio fecha no total do balanço."""
    imo = {r: v for r, v in bp[ano]["industria"]["ANC"]["Imobilizado"]}
    dep_total = -imo.get("(-) Depreciação acumulada", 0)
    classes = [(r, v, TAXAS.get(r, 0.0)) for r, v in imo.items() if not r.startswith("(-)")]
    base = sum(v * t for _, v, t in classes)
    linhas, acum = [], 0
    depreciaveis = [x for x in classes if x[2] > 0]
    for i, (rot, custo, taxa) in enumerate(classes):
        if taxa == 0:
            linhas.append((rot, custo, taxa, 0, custo))
            continue
        ultimo = rot == depreciaveis[-1][0]
        d = dep_total - acum if ultimo else int(round(dep_total * custo * taxa / base))
        acum += d
        linhas.append((rot, custo, taxa, d, custo - d))
    assert sum(x[3] for x in linhas) == dep_total, "depreciação rateada não fecha"
    liquido = sum(x[4] for x in linhas)
    return linhas, sum(x[1] for x in linhas), dep_total, liquido


# ---------------------------------------------------------------------------
# FOLHA DE PAGAMENTO — headcount (não monetário) ao lado do custo.
# ---------------------------------------------------------------------------
AREAS = [
    ("Produção - turno A", 148, 96, 4.12),
    ("Produção - turno B", 132, 84, 4.08),
    ("Manutenção industrial", 34, 22, 6.40),
    ("Expedição e logística interna", 41, 26, 3.60),
    ("Qualidade e laboratório", 12, 9, 5.90),
    ("Comercial e atendimento", 26, 19, 7.80),
    ("Administrativo e financeiro", 22, 18, 8.60),
    ("Diretoria", 5, 5, 42.00),
]


def folha(ano=2025):
    """Headcount por área × salário médio. A coluna de pessoas NÃO é dinheiro —
    um extrator que herdar a escala do documento transforma 148 funcionários em
    R$ 148 mil."""
    linhas = []
    for area, hc_2023, hc_2025, medio in AREAS:
        hc = {2023: hc_2023, 2024: int(round((hc_2023 + hc_2025) / 2)), 2025: hc_2025}[ano]
        custo_mensal = round(hc * medio, 1)
        linhas.append((area, hc, medio, custo_mensal, round(custo_mensal * 13.33, 1)))
    return linhas, sum(x[1] for x in linhas), round(sum(x[4] for x in linhas), 1)


# ---------------------------------------------------------------------------
# EXTRATO BANCÁRIO CONSOLIDADO — soma = Disponível do balanço.
# ---------------------------------------------------------------------------
BANCOS = [
    ("Banco Meridional S.A.", "0341", "12.884-7", "Conta corrente", .34),
    ("Banco Praia Grande S.A.", "0212", "55.019-0", "Conta corrente", .26),
    ("Banco Serra Norte S.A.", "0770", "9.443-2", "Conta corrente", .18),
    ("Banco de Fomento Nacional", "0104", "31.220-5", "Conta vinculada FINAME", .12),
    ("Caixa e fundo fixo (matriz e filiais)", "-", "-", "Numerário em espécie", .10),
]


def extratos(bp, ano=2025):
    disp = M.soma_folhas({"x": bp[ano]["industria"]["AC"]["Disponível"]})
    linhas, acum = [], 0
    for i, (banco, ag, cc, tipo, peso) in enumerate(BANCOS):
        ultimo = i == len(BANCOS) - 1
        v = disp - acum if ultimo else int(round(disp * peso))
        acum += v
        linhas.append((banco, ag, cc, tipo, v))
    assert sum(x[4] for x in linhas) == disp, "extratos não batem com o Disponível"
    return linhas, disp


# ---------------------------------------------------------------------------
# DFC — método indireto, amarrado ao caixa do balanço.
# ---------------------------------------------------------------------------
def dfc(bp, tot, ano=2025):
    ant = ANOS[ANOS.index(ano) - 1]
    var = variacoes(bp, tot)[ano]
    resultado = resultado_alvo(tot)[ano]

    def disp(a):
        return M.soma_folhas({"x": bp[a]["industria"]["AC"]["Disponível"]})

    def bloco(a, secao, ignora=()):
        s = 0
        for sub, contas in bp[a]["industria"][secao].items():
            if sub in ignora:
                continue
            s += sum(v for _, v in contas)
        return s

    caixa_ini, caixa_fim = disp(ant), disp(ano)

    # Variação das contas operacionais (tudo do circulante menos caixa e dívida).
    op_ativo = (bloco(ano, "AC", ignora=("Disponível",)) - bloco(ant, "AC", ignora=("Disponível",)))
    op_passivo_subs = ("Fornecedores", "Obrigações Trabalhistas e Sociais",
                       "Obrigações Tributárias", "Outras Obrigações")
    op_passivo = (sum(sum(v for _, v in bp[ano]["industria"]["PC"].get(s, [])) for s in op_passivo_subs)
                  - sum(sum(v for _, v in bp[ant]["industria"]["PC"].get(s, [])) for s in op_passivo_subs))

    # Investimento: variação do custo do imobilizado e do intangível (bruto).
    def bruto(a, sub):
        return sum(v for r, v in bp[a]["industria"]["ANC"].get(sub, []) if not r.startswith("(-)"))
    capex = -((bruto(ano, "Imobilizado") - bruto(ant, "Imobilizado"))
              + (bruto(ano, "Intangível") - bruto(ant, "Intangível")))

    # Financiamento: dívida bancária, arrendamentos, mútuos com a holding.
    def fin(a):
        pc = sum(v for _, v in bp[a]["industria"]["PC"].get("Empréstimos e Financiamentos", []))
        pnc = sum(v for _, v in bp[a]["industria"]["PNC"].get("Empréstimos e Financiamentos", []))
        arr = (sum(v for _, v in bp[a]["industria"]["PC"].get("Arrendamentos", []))
               + sum(v for _, v in bp[a]["industria"]["PNC"].get("Arrendamentos", [])))
        mut = sum(v for _, v in bp[a]["industria"]["PC"].get("Partes Relacionadas", []))
        return pc + pnc, arr, mut
    d_ano, arr_ano, mut_ano = fin(ano)
    d_ant, arr_ant, mut_ant = fin(ant)
    financiamento = (d_ano - d_ant) + (arr_ano - arr_ant) + (mut_ano - mut_ant)

    naocaixa = (var["depreciacao"] + var["amort_du"] + var["amort_intangivel"]
                + var["pecld"] + var["obsolescencia"] + var["provisoes"] - var["ir_diferido"])

    # A linha que fecha o fluxo: variação de contas não circulantes operacionais
    # e de tributos parcelados, que não cabem em nenhum dos blocos acima.
    fco_parcial = resultado + naocaixa - op_ativo + op_passivo
    outras = (caixa_fim - caixa_ini) - (fco_parcial + capex + financiamento)
    fco = fco_parcial + outras

    linhas = [
        ("FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS", None, "ancora"),
        ("Prejuízo do exercício" if resultado < 0 else "Lucro do exercício", resultado, "conta"),
        ("Depreciação e amortização", var["depreciacao"] + var["amort_du"] + var["amort_intangivel"], "conta"),
        ("Perdas estimadas em créditos de liquidação duvidosa", var["pecld"], "conta"),
        ("Provisão para obsolescência de estoques", var["obsolescencia"], "conta"),
        ("Provisão para contingências", var["provisoes"], "conta"),
        ("Imposto de renda e contribuição social diferidos", -var["ir_diferido"], "conta"),
        ("(Aumento) redução de contas do ativo operacional", -op_ativo, "conta"),
        ("Aumento (redução) de contas do passivo operacional", op_passivo, "conta"),
        ("Outras variações operacionais, líquidas", outras, "conta"),
        ("Caixa líquido gerado (consumido) pelas atividades operacionais", fco, "subtotal"),
        ("FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO", None, "ancora"),
        ("Aquisições de imobilizado e intangível", capex, "conta"),
        ("Caixa líquido consumido pelas atividades de investimento", capex, "subtotal"),
        ("FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO", None, "ancora"),
        ("Captações (amortizações) líquidas de empréstimos e arrendamentos",
         (d_ano - d_ant) + (arr_ano - arr_ant), "conta"),
        ("Mútuos com partes relacionadas, líquidos", mut_ano - mut_ant, "conta"),
        ("Caixa líquido gerado pelas atividades de financiamento", financiamento, "subtotal"),
        ("AUMENTO (REDUÇÃO) LÍQUIDO DE CAIXA E EQUIVALENTES", caixa_fim - caixa_ini, "ancora"),
        ("Caixa e equivalentes no início do exercício", caixa_ini, "conta"),
        ("Caixa e equivalentes no fim do exercício", caixa_fim, "ancora"),
    ]
    assert fco + capex + financiamento == caixa_fim - caixa_ini, "DFC não fecha no caixa"
    return linhas, caixa_ini, caixa_fim


# ---------------------------------------------------------------------------
# DMPL — três exercícios. As linhas "SALDOS EM 31 DE DEZEMBRO DE ..." são
# subtotais e NÃO podem ser somadas ao PL (armadilha herdada do book anterior,
# aqui multiplicada por três).
# ---------------------------------------------------------------------------
def dmpl(bp, tot):
    alvo = resultado_alvo(tot)
    colunas = ["Capital social", "Reserva legal", "Reserva de lucros a realizar",
               "Lucros (prejuízos) acumulados", "Total"]

    def pl_conta(ano, prefixo):
        for sub in bp[ano]["industria"]["PL"].values():
            for rot, v in sub:
                if rot.startswith(prefixo):
                    return v
        return 0

    def saldo(ano):
        cap = pl_conta(ano, "Capital social")
        leg = pl_conta(ano, "Reserva legal")
        rea = pl_conta(ano, "Reserva de lucros")
        acum = pl_conta(ano, "Lucros acumulados") or pl_conta(ano, "Prejuízos acumulados")
        return [cap, leg, rea, acum, cap + leg + rea + acum]

    s23 = saldo(2023)
    s24 = saldo(2024)
    s25 = saldo(2025)
    # 2022 é reconstruído a partir de 2023: PL anterior = PL 2023 − lucro + dividendos.
    s22 = [s23[0], s23[1], s23[2], s23[3] - LUCRO_2023 + DIVIDENDOS_2023, 0]
    s22[4] = sum(s22[:4])

    linhas = [
        ("SALDOS EM 31 DE DEZEMBRO DE 2022", s22, "saldo"),
        ("Lucro líquido do exercício de 2023", [0, 0, 0, LUCRO_2023, LUCRO_2023], "mov"),
        ("Dividendos deliberados e pagos", [0, 0, 0, -DIVIDENDOS_2023, -DIVIDENDOS_2023], "mov"),
        ("SALDOS EM 31 DE DEZEMBRO DE 2023", s23, "saldo"),
        ("Prejuízo do exercício de 2024", [0, 0, 0, alvo[2024], alvo[2024]], "mov"),
        ("Realização da reserva de lucros a realizar", [0, 0, -s23[2], s23[2], 0], "mov"),
        ("SALDOS EM 31 DE DEZEMBRO DE 2024", s24, "saldo"),
        ("Prejuízo do exercício de 2025", [0, 0, 0, alvo[2025], alvo[2025]], "mov"),
        ("SALDOS EM 31 DE DEZEMBRO DE 2025", s25, "saldo"),
    ]
    # As três amarrações da DMPL, cada uma com um assert:
    assert s23[4] == tot[2023]["industria"]["PL"], "DMPL 2023 não bate com o balanço"
    assert s24[4] == tot[2024]["industria"]["PL"], "DMPL 2024 não bate com o balanço"
    assert s25[4] == tot[2025]["industria"]["PL"], "DMPL 2025 não bate com o balanço"
    soma24 = [s23[k] + linhas[4][1][k] + linhas[5][1][k] for k in range(5)]
    assert soma24 == s24, f"movimentação de 2024 não leva 2023 a 2024: {soma24} != {s24}"
    soma25 = [s24[k] + linhas[7][1][k] for k in range(5)]
    assert soma25 == s25, f"movimentação de 2025 não leva 2024 a 2025: {soma25} != {s25}"
    return colunas, linhas


# ---------------------------------------------------------------------------
# DVA — o valor adicionado e sua distribuição. Fecha por construção.
# ---------------------------------------------------------------------------
def dva(bp, tot, ano=2025):
    linhas_dre = dre_industria(bp, tot)[ano]
    a = ancoras(linhas_dre)
    d = {r: v for r, v, t in linhas_dre}
    var = variacoes(bp, tot)[ano]

    receitas = a["RECEITA OPERACIONAL BRUTA"] + d["(-) Perdas estimadas em créditos de liquidação duvidosa"]
    insumos = (d["(-) Matérias-primas e insumos consumidos"]
               + d["(-) Energia elétrica, gás e utilidades industriais"]
               + d["(-) Outros custos de produção"]
               + d["(-) Despesas com vendas, fretes e comissões"]
               + d["(-) Despesas gerais e administrativas"])
    va_bruto = receitas + insumos
    depreciacao = -var["dea_total"]
    va_liquido = va_bruto + depreciacao
    recebido = d["Receitas financeiras"]
    va_distribuir = va_liquido + recebido

    pessoal = d["(-) Mão de obra direta e encargos sociais"] + d["(-) Honorários da administração"]
    impostos = (d["(-) ICMS sobre vendas"] + d["(-) PIS e COFINS sobre vendas"]
                + d["(-) Imposto de renda e contribuição social correntes"]
                + d.get("Imposto de renda e contribuição social diferidos", 0))
    terceiros = d["(-) Despesas financeiras"] + d.get("Variações cambiais líquidas", 0)
    proprios = a["PREJUÍZO DO EXERCÍCIO"] if "PREJUÍZO DO EXERCÍCIO" in a else a["LUCRO LÍQUIDO DO EXERCÍCIO"]
    # A DVA distribui exatamente o que apurou; a diferença residual (linhas da
    # DRE que não são nem insumo nem distribuição) vai para "outras".
    nomeadas = [
        ("Pessoal e encargos", -pessoal),
        ("Impostos, taxas e contribuições", -impostos),
        ("Remuneração de capitais de terceiros (juros e variações cambiais)", -terceiros),
    ]
    # O que sobra do valor adicionado depois das destinações nomeadas e do
    # resultado do exercício: provisões, perdas e depreciações já deduzidas de
    # outra forma. É o resíduo declarado, não um número escolhido.
    residuo = va_distribuir - sum(v for _, v in nomeadas) - proprios
    distribuicao = nomeadas + [
        ("Outras destinações (provisões, perdas e baixas do exercício)", residuo),
        ("Remuneração de capitais próprios (prejuízo do exercício)", proprios),
    ]
    assert sum(v for _, v in distribuicao) == va_distribuir, (
        f"DVA não fecha: distribuído {sum(v for _, v in distribuicao)} × apurado {va_distribuir}")
    geracao = [
        ("RECEITAS", receitas, "ancora"),
        ("Receita bruta de vendas e serviços", a["RECEITA OPERACIONAL BRUTA"], "conta"),
        ("Perdas estimadas em créditos de liquidação duvidosa",
         d["(-) Perdas estimadas em créditos de liquidação duvidosa"], "conta"),
        ("(-) INSUMOS ADQUIRIDOS DE TERCEIROS", insumos, "ancora"),
        ("Matérias-primas, energia, serviços e outros custos", insumos, "conta"),
        ("VALOR ADICIONADO BRUTO", va_bruto, "ancora"),
        ("(-) Depreciação e amortização", depreciacao, "conta"),
        ("VALOR ADICIONADO LÍQUIDO PRODUZIDO", va_liquido, "ancora"),
        ("Valor adicionado recebido em transferência (receitas financeiras)", recebido, "conta"),
        ("VALOR ADICIONADO TOTAL A DISTRIBUIR", va_distribuir, "ancora"),
    ]
    return geracao, distribuicao, va_distribuir


# ---------------------------------------------------------------------------
# RAZÃO ANALÍTICO — lançamento a lançamento de UMA conta. Documento longo de
# propósito: é o que mede o teto de linhas do preparo de conteúdo.
# ---------------------------------------------------------------------------
HISTORICOS = [
    "NF 0{n} - Papéis e Celulose Aracati S.A. - bobina kraft 180g",
    "NF 0{n} - Tintas e Adesivos Ipiranga Ltda. - adesivo industrial",
    "Pagto TED - Papéis e Celulose Aracati S.A.",
    "NF 0{n} - Energia Distribuidora do Sudeste S.A. - fatura mensal",
    "Pagto boleto - Transportadora Rota Norte Ltda.",
    "NF 0{n} - Aparas e Reciclagem Bom Retiro Ltda.",
    "Estorno de duplicata cancelada - NF 0{n}",
    "Pagto parcial - acordo de renegociação",
]


def razao_fornecedores(bp, ano=2025, lancamentos=96):
    """Movimento de dezembro da conta `Fornecedores nacionais`, fechando no
    saldo do balanço. Débito e crédito em colunas separadas, com natureza."""
    saldo_final = M.valor_conta(bp[ano]["industria"], "PC", "Fornecedores", "Fornecedores nacionais")
    linhas, saldo = [], int(round(saldo_final * 0.93))
    abertura = saldo
    creditos = debitos = 0
    for i in range(lancamentos):
        dia = 1 + (i * 29) % 30
        hist = HISTORICOS[i % len(HISTORICOS)].replace("{n}", f"{10_000 + i * 37}")
        if i % 3 == 2:
            valor = 120 + (i * 53) % 900
            saldo -= valor
            debitos += valor
            linhas.append((f"{dia:02d}/12/{ano}", f"LC-{ano}-{4000 + i}", hist, valor, 0, saldo, "C"))
        else:
            valor = 150 + (i * 71) % 1_200
            saldo += valor
            creditos += valor
            linhas.append((f"{dia:02d}/12/{ano}", f"LC-{ano}-{4000 + i}", hist, 0, valor, saldo, "C"))
    # A última linha ajusta para o saldo do balanço — é o lançamento de
    # fechamento que todo razão real tem.
    ajuste = saldo_final - saldo
    if ajuste >= 0:
        linhas.append((f"31/12/{ano}", f"LC-{ano}-9999", "Apropriação de encargos e ajuste de fechamento",
                       0, ajuste, saldo_final, "C"))
        creditos += ajuste
    else:
        linhas.append((f"31/12/{ano}", f"LC-{ano}-9999", "Reversão de provisão e ajuste de fechamento",
                       -ajuste, 0, saldo_final, "C"))
        debitos += -ajuste
    assert linhas[-1][5] == saldo_final, "razão não fecha no saldo do balanço"
    return linhas, abertura, debitos, creditos, saldo_final


# ---------------------------------------------------------------------------
# BALANCETE ANALÍTICO — natureza D/C, dois exercícios lado a lado.
# ---------------------------------------------------------------------------
def balancete(bp, ano, ent="industria"):
    """Devolve [(código, conta, saldo, natureza)] — a NATUREZA é que dá o sinal,
    e o valor sai sempre em módulo, como num balancete de verdade."""
    linhas = []
    codigos = {"AC": "1.1", "ANC": "1.2", "PC": "2.1", "PNC": "2.2", "PL": "2.3"}
    for secao in ("AC", "ANC", "PC", "PNC", "PL"):
        i = 0
        for sub, contas in bp[ano][ent][secao].items():
            i += 1
            j = 0
            for rot, v in contas:
                j += 1
                natureza = "D" if secao in ("AC", "ANC") else "C"
                # Conta redutora inverte a natureza — é o detalhe que faz o
                # sinal depender da coluna D/C e não do rótulo.
                if v < 0:
                    natureza = "C" if natureza == "D" else "D"
                linhas.append((f"{codigos[secao]}.{i:02d}.{j:03d}", rot, abs(v), natureza))
    return linhas


# ---------------------------------------------------------------------------
# DRE CONDENSADA das demais empresas do grupo. Doze linhas, e o resultado é a
# variação do PL delas — mesma disciplina da DRE completa, em escala menor.
# ---------------------------------------------------------------------------
def dre_condensada(bp, tot, ent, receita, anos):
    """`receita` é {ano: receita bruta em R$ mil}. Devolve
    [(rótulo, [valor por ano], tipo)] com os anos NA ORDEM PEDIDA."""
    blocos = {}
    for ano in anos:
        ant = ANOS[ANOS.index(ano) - 1]
        alvo = tot[ano][ent]["PL"] - tot[ant][ent]["PL"]
        rb = receita[ano]
        ded = -round(rb * .148)
        rl = rb + ded
        cmv = -round(rl * (.79 if ent == "comercial" else .72))
        lb = rl + cmv
        desp = -round(rl * .17)
        # A dívida da empresa remunera a taxa média do grupo.
        div = (sum(v for _, v in bp[ano][ent]["PC"].get("Empréstimos", []))
               + sum(v for _, v in bp[ano][ent]["PNC"].get("Empréstimos", [])))
        fin = -round(div * .24)
        outras = alvo - (lb + desp + fin)
        ebit = lb + desp + outras
        blocos[ano] = [
            ("RECEITA OPERACIONAL BRUTA", rb, "ancora"),
            ("(-) Deduções, devoluções e impostos sobre vendas", ded, "conta"),
            ("RECEITA OPERACIONAL LÍQUIDA", rl, "ancora"),
            ("(-) Custo das mercadorias vendidas e dos serviços prestados", cmv, "conta"),
            ("LUCRO BRUTO", lb, "ancora"),
            ("(-) Despesas operacionais, comerciais e administrativas", desp, "conta"),
            ("Outras receitas (despesas) operacionais, líquidas", outras, "conta"),
            ("RESULTADO ANTES DO RESULTADO FINANCEIRO", ebit, "ancora"),
            ("Resultado financeiro líquido", fin, "conta"),
            ("PREJUÍZO DO EXERCÍCIO" if alvo < 0 else "LUCRO LÍQUIDO DO EXERCÍCIO", alvo, "ancora"),
        ]
        assert ebit + fin == alvo, f"DRE condensada de {ent}/{ano} não fecha"

    ordem = [r for r, _v, _t in blocos[anos[0]]]
    tipos = {r: t for r, _v, t in blocos[anos[0]]}
    return [(r, [dict((x, v) for x, v, _t in blocos[a]).get(r) for a in anos], tipos[r])
            for r in ordem]
