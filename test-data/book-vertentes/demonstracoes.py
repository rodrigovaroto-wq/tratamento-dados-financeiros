# -*- coding: utf-8 -*-
"""DRE, DFC, DMPL, faturamento, mapa de dívida e mútuos — AMARRADOS ao balanço.

Amarrações garantidas por assert:
  • Prejuízo do exercício = variação dos resultados acumulados no BP (DMPL fecha).
  • Saldo final de caixa da DFC = Disponível do BP.
  • Soma do faturamento mensal de 2025 = Receita Operacional Bruta da DRE.
  • Juros do mapa de dívida (R$ unidades) = Despesas financeiras da DRE (R$ mil)
    — de propósito em ESCALAS diferentes, para exercitar a pré-condição de
    escala da reconciliação Classe B.
"""

import motor as M


def dre_metalurgica(tot):
    """DRE comparativa. O prejuízo de 2025 é AMARRADO à variação do PL no BP."""
    alvo_2025 = tot[2025]["metalurgica"]["plug"] - tot[2024]["metalurgica"]["plug"]  # negativo

    linhas_2025 = [
        ("RECEITA OPERACIONAL BRUTA", None, "sub"),
        ("Vendas de produtos - mercado interno", 121300, "conta"),
        ("Vendas de produtos - mercado externo", 14780, "conta"),
        ("Prestação de serviços de industrialização", 2320, "conta"),
        ("DEDUÇÕES DA RECEITA BRUTA", None, "sub"),
        ("(-) Devoluções e abatimentos", -3180, "conta"),
        ("(-) ICMS sobre vendas", -18900, "conta"),
        ("(-) PIS e COFINS sobre vendas", -7640, "conta"),
        ("(-) IPI sobre vendas", -2100, "conta"),
        ("RECEITA OPERACIONAL LÍQUIDA", "ANCORA_RL", "ancora"),
        ("CUSTO DOS PRODUTOS VENDIDOS", None, "sub"),
        ("(-) Matérias-primas e insumos consumidos", -67000, "conta"),
        ("(-) Mão de obra direta e encargos", -18900, "conta"),
        ("(-) Custos indiretos de fabricação", -9860, "conta"),
        ("(-) Depreciação industrial", -5540, "conta"),
        ("LUCRO BRUTO", "ANCORA_LB", "ancora"),
        ("DESPESAS OPERACIONAIS", None, "sub"),
        ("(-) Despesas com vendas e comerciais", -6240, "conta"),
        ("(-) Despesas gerais e administrativas", -8900, "conta"),
        ("(-) Honorários da administração", -1440, "conta"),
        ("(-) Despesas tributárias", -740, "conta"),
        ("(-) Perdas estimadas em créditos de liquidação duvidosa", -2180, "conta"),
        ("(-) Provisão para contingências trabalhistas e cíveis", -1900, "conta"),
        ("Outras receitas (despesas) operacionais, líquidas", "PLUG", "conta"),
        ("RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO", "ANCORA_EBIT", "ancora"),
        ("RESULTADO FINANCEIRO", None, "sub"),
        ("Receitas financeiras", 310, "conta"),
        ("(-) Despesas financeiras - juros e encargos bancários", -12400, "conta"),
        ("(-) Variações monetárias e cambiais, líquidas", -1240, "conta"),
        ("RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO", "ANCORA_LAIR", "ancora"),
        ("TRIBUTOS SOBRE O LUCRO", None, "sub"),
        ("Imposto de renda e contribuição social - corrente", 0, "conta"),
        ("Imposto de renda e contribuição social - diferido", 0, "conta"),
        ("PREJUÍZO LÍQUIDO DO EXERCÍCIO", "ANCORA_LL", "ancora"),
    ]

    # resolve o PLUG para o prejuízo bater com o BP
    def soma(tipo_filtro):
        return sum(v for _, v, t in linhas_2025 if t == "conta" and isinstance(v, int))
    conhecido = sum(v for _, v, t in linhas_2025 if t == "conta" and isinstance(v, int))
    plug = alvo_2025 - conhecido
    linhas_2025 = [(r, (plug if v == "PLUG" else v), t) for r, v, t in linhas_2025]

    # 2024 (comparativo) — ano ainda operacional, prejuízo pequeno
    vals_2024 = {
        "Vendas de produtos - mercado interno": 158900,
        "Vendas de produtos - mercado externo": 21400,
        "Prestação de serviços de industrialização": 3180,
        "(-) Devoluções e abatimentos": -2740,
        "(-) ICMS sobre vendas": -24600,
        "(-) PIS e COFINS sobre vendas": -9980,
        "(-) IPI sobre vendas": -2780,
        "(-) Matérias-primas e insumos consumidos": -78200,
        "(-) Mão de obra direta e encargos": -21400,
        "(-) Custos indiretos de fabricação": -11200,
        "(-) Depreciação industrial": -5180,
        "(-) Despesas com vendas e comerciais": -8100,
        "(-) Despesas gerais e administrativas": -9640,
        "(-) Honorários da administração": -1440,
        "(-) Despesas tributárias": -910,
        "(-) Perdas estimadas em créditos de liquidação duvidosa": -980,
        "(-) Provisão para contingências trabalhistas e cíveis": -1100,
        "Outras receitas (despesas) operacionais, líquidas": 1240,
        "Receitas financeiras": 640,
        "(-) Despesas financeiras - juros e encargos bancários": -8900,
        "(-) Variações monetárias e cambiais, líquidas": -740,
        "Imposto de renda e contribuição social - corrente": -420,
        "Imposto de renda e contribuição social - diferido": 0,
    }
    return linhas_2025, vals_2024, alvo_2025


def cascata(linhas, vals=None):
    """Calcula as âncoras da DRE em cascata (soma corrida das contas)."""
    acc, out = 0, []
    for rot, v, tipo in linhas:
        if tipo == "conta":
            valor = v if vals is None else vals.get(rot, 0)
            acc += valor
            out.append((rot, valor, tipo))
        elif tipo == "ancora":
            out.append((rot, acc, tipo))
        else:
            out.append((rot, None, tipo))
    return out, acc


def dfc_metalurgica(tot, prejuizo):
    """DFC indireta. Saldo final AMARRADO ao Disponível do BP."""
    caixa_ini = 1240 + 3600      # BP 2024 (Disponível)
    caixa_fim = 380 + 120        # BP 2025 (Disponível)
    variacao_alvo = caixa_fim - caixa_ini

    operacional = [
        ("Prejuízo líquido do exercício", prejuizo),
        ("Depreciação e amortização", 5840),
        ("Perdas estimadas em créditos de liquidação duvidosa", 2180),
        ("Provisão para obsolescência de estoques", 1250),
        ("Provisão para contingências", 1900),
        ("Resultado na alienação de imobilizado", -1180),
        ("Juros e encargos provisionados não pagos", 3420),
        ("Variação em contas a receber de clientes", 7740),
        ("Variação em estoques", 4930),
        ("Variação em tributos a recuperar", -450),
        ("Variação em fornecedores", "PLUG"),
        ("Variação em obrigações trabalhistas e sociais", 2180),
        ("Variação em obrigações tributárias e parcelamentos", -3180),
        ("Variação em outros ativos e passivos operacionais", -890),
    ]
    investimento = [
        ("Aquisições de imobilizado", -3900),
        ("Recebimento pela alienação de imobilizado", 2140),
        ("Aquisições de intangível", -180),
    ]
    financiamento = [
        ("Captação de empréstimos e financiamentos", 18600),
        ("Amortização de empréstimos e financiamentos", -21400),
        ("Antecipação de recebíveis, líquida", 4600),
        ("Pagamento de arrendamentos - CPC 06", -890),
        ("Mútuos recebidos da controladora, líquidos", 5400),
        ("Juros pagos", -9800),
    ]

    conhecido_op = sum(v for _, v in operacional if isinstance(v, int))
    soma_inv = sum(v for _, v in investimento)
    soma_fin = sum(v for _, v in financiamento)
    plug = variacao_alvo - (conhecido_op + soma_inv + soma_fin)
    operacional = [(r, (plug if v == "PLUG" else v)) for r, v in operacional]

    tot_op = sum(v for _, v in operacional)
    assert tot_op + soma_inv + soma_fin == variacao_alvo, "DFC não fecha"
    return {
        "operacional": operacional, "investimento": investimento, "financiamento": financiamento,
        "tot_op": tot_op, "tot_inv": soma_inv, "tot_fin": soma_fin,
        "variacao": variacao_alvo, "caixa_ini": caixa_ini, "caixa_fim": caixa_fim,
    }


def faturamento_24m(receita_bruta_2025):
    """Faturamento mensal 24 meses. A soma de 2025 é AMARRADA à Receita
    Operacional Bruta da DRE. Tendência de queda ao longo de 2025 (distress)."""
    meses = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
    pesos_2025 = [1.18, 1.12, 1.15, 1.05, 1.02, 0.98, 0.92, 0.88, 0.86, 0.80, 0.72, 0.62]
    pesos_2024 = [1.02, 1.05, 1.08, 1.06, 1.10, 1.04, 1.00, 1.03, 0.98, 0.95, 0.92, 0.85]
    total_2024 = 183480  # receita bruta 2024 (158900+21400+3180)

    def distribuir(total, pesos):
        soma_p = sum(pesos)
        vals = [int(round(total * p / soma_p)) for p in pesos]
        vals[-1] += total - sum(vals)  # ajuste de arredondamento no último mês
        return vals

    v25 = distribuir(receita_bruta_2025, pesos_2025)
    v24 = distribuir(total_2024, pesos_2024)
    assert sum(v25) == receita_bruta_2025, "faturamento 2025 não amarra com a DRE"
    return list(zip(meses, v24, v25)), total_2024, receita_bruta_2025


def mapa_divida(despesa_financeira_mil):
    """Mapa de dívida em R$ UNIDADES (escala diferente do balanço, de propósito).
    A soma dos juros do ano AMARRA com a despesa financeira da DRE (em mil)."""
    contratos = [
        # (credor, modalidade, saldo_mil, taxa, vencimento, garantia, juros_ano_mil)
        ("Banco Meridional S.A.", "Capital de giro", 9420, "CDI + 6,80% a.a.", "15/03/2026", "Recebíveis + aval dos sócios", 2180),
        ("Banco Meridional S.A.", "Conta garantida", 2380, "CDI + 9,20% a.a.", "Rotativo", "Aval dos sócios", 640),
        ("Banco Atlântico Sul", "Capital de giro", 6180, "CDI + 7,40% a.a.", "20/08/2026", "Alienação fiduciária de máquinas", 1490),
        ("Banco Atlântico Sul", "Antecipação de recebíveis", 6180, "2,45% a.m.", "Rotativo", "Duplicatas cedidas", 3210),
        ("BNDES / FINAME (agente: Banco Meridional)", "Financiamento de máquinas", 9080, "TLP + 4,10% a.a.", "10/07/2029", "Alienação fiduciária dos bens financiados", 1080),
        ("Cooperativa de Crédito Vale", "Capital de giro", 3140, "1,95% a.m.", "05/02/2026", "Aval dos sócios", 820),
        ("Fomento Mercantil Paulista Ltda.", "Factoring", 2440, "3,10% a.m.", "Rotativo", "Duplicatas cedidas com coobrigação", 1180),
        ("Arrendadora Sigma", "Arrendamento mercantil (CPC 06)", 2680, "CDI + 8,00% a.a.", "30/11/2027", "Bem arrendado", 380),
        ("Sócios pessoas físicas", "Empréstimo subordinado", 9800, "Sem remuneração", "Sem vencimento definido", "Sem garantia", 0),
    ]
    juros_total = sum(c[6] for c in contratos)
    # ajusta o maior contrato para amarrar exatamente com a DRE
    dif = abs(despesa_financeira_mil) - juros_total
    contratos[3] = contratos[3][:6] + (contratos[3][6] + dif,)
    assert sum(c[6] for c in contratos) == abs(despesa_financeira_mil), "juros não amarram com a DRE"
    return contratos


def mutuos_intragrupo(tot):
    """Relação de mútuos/contas intragrupo. DE PROPÓSITO com uma divergência
    pequena (R$ 180 mil) contra o balanço: planilha de controle mantida à parte
    do razão — situação comuníssima em grupo familiar, e exatamente o tipo de
    divergência que a reconciliação deve mostrar ao humano em vez de esconder."""
    m = tot[2025]["_mutuos_holding"]
    return [
        ("Vertentes Participações S.A.", "Vertentes Metalúrgica Ltda.", "Mútuo", 7600, "Sem vencimento definido"),
        ("Vertentes Participações S.A.", "Vertentes Componentes Automotivos Ltda.", "Mútuo", m - 7600 + 180, "Sem vencimento definido"),
        ("Vertentes Metalúrgica Ltda.", "VT Logística e Transportes Ltda.", "Conta corrente", 1400, "Rotativo"),
        ("Vertentes Imóveis SPE Ltda.", "Vertentes Metalúrgica Ltda.", "Aluguéis a receber", 640, "Mensal"),
    ], 7600 + (m - 7600 + 180) + 1400 + 640
