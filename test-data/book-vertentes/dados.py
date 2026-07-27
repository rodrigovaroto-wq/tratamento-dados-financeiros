# -*- coding: utf-8 -*-
"""
Book de teste — Grupo VERTENTES (empresa fictícia em dificuldade financeira).

Dados SINTÉTICOS. O objetivo é estressar o pipeline de tratamento de dados com
complexidade de vida real: grupo com 5 empresas, plano de contas detalhado
(4 níveis), comparativo multi-ano, combinado com eliminações e participação de
não controladores, escalas diferentes entre documentos, sinais em parênteses,
nomenclatura idiossincrática por empresa e sinais clássicos de distress
(covenant quebrado com reclassificação de LP→CP, parcelamentos tributários,
antecipação de recebíveis, PL negativo numa controlada, going concern).

Tudo em R$ MIL, exceto onde explicitado (o mapa de dívida sai em R$ unidades de
propósito, para exercitar a pré-condição de escala da reconciliação Classe B).

O módulo COMPUTA os subtotais e VALIDA as amarrações (assert) — nenhum total é
digitado à mão.
"""

# ---------------------------------------------------------------------------
# Estrutura: cada entidade tem contas-folha por ano. Subtotais são calculados.
# 'pl_plug' = conta que absorve o fechamento (Prejuízos Acumulados) — é o que
# acontece de verdade numa empresa que vem acumulando perdas.
# ---------------------------------------------------------------------------

GRUPO = "GRUPO VERTENTES"

ENTIDADES = {
    "holding": {
        "razao_social": "VERTENTES PARTICIPAÇÕES S.A.",
        "cnpj": "11.222.333/0001-44",
        # rótulos próprios (cada empresa nomeia diferente — de propósito)
        "rotulo_caixa": "Caixa e Equivalentes de Caixa",
    },
    "metalurgica": {
        "razao_social": "VERTENTES METALÚRGICA LTDA.",
        "cnpj": "11.222.334/0001-08",
        "rotulo_caixa": "Disponibilidades",
    },
    "componentes": {
        "razao_social": "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.",
        "cnpj": "11.222.335/0001-71",
        "rotulo_caixa": "Numerário Disponível",
    },
    "logistica": {
        "razao_social": "VT LOGÍSTICA E TRANSPORTES LTDA.",
        "cnpj": "11.222.336/0001-15",
        "rotulo_caixa": "Bancos Conta Movimento",
    },
    "spe": {
        "razao_social": "VERTENTES IMÓVEIS SPE LTDA.",
        "cnpj": "11.222.337/0001-59",
        "rotulo_caixa": "Caixa",
    },
}

# Participação da holding em cada controlada
PARTICIPACAO = {"metalurgica": 1.00, "componentes": 1.00, "logistica": 0.70, "spe": 1.00}

# ---------------------------------------------------------------------------
# BALANÇO — contas-folha por entidade e ano (R$ mil).
# Chaves seguem o formato (grupo, secao, subsecao, conta).
# Valores de contas redutoras vão NEGATIVOS (o PDF os imprime entre parênteses).
# ---------------------------------------------------------------------------

def bp_metalurgica():
    return {
        2025: {
            "AC": {
                "Disponível": [
                    ("Caixa e bancos conta movimento", 380),
                    ("Aplicações financeiras de liquidez imediata", 120),
                ],
                "Contas a Receber": [
                    ("Duplicatas a receber de clientes - mercado interno", 21400),
                    ("Duplicatas a receber de clientes - mercado externo", 2860),
                    ("(-) Perdas estimadas em créditos de liquidação duvidosa", -3850),
                ],
                "Estoques": [
                    ("Matérias-primas e insumos", 9200),
                    ("Produtos em elaboração", 3100),
                    ("Produtos acabados", 6400),
                    ("Materiais de manutenção e consumo", 780),
                    ("(-) Provisão para obsolescência de estoques", -2350),
                ],
                "Tributos a Recuperar": [
                    ("ICMS a recuperar", 2640),
                    ("PIS e COFINS a recuperar", 1180),
                    ("IRRF sobre aplicações financeiras", 210),
                ],
                "Outros Créditos": [
                    ("Adiantamentos a fornecedores", 1320),
                    ("Adiantamentos a empregados", 460),
                    ("Despesas antecipadas - seguros e apólices", 190),
                ],
            },
            "ANC": {
                "Realizável a Longo Prazo": [
                    ("Créditos tributários - ICMS sobre ativo permanente", 3400),
                    ("Depósitos judiciais - trabalhistas", 3120),
                    ("Depósitos judiciais - tributários", 1730),
                    ("Títulos a receber - venda de imobilizado", 620),
                ],
                "Investimentos": [
                    ("Participações em outras sociedades - avaliadas ao custo", 180),
                ],
                "Imobilizado": [
                    ("Terrenos", 8500),
                    ("Edificações e benfeitorias", 24000),
                    ("Máquinas, aparelhos e equipamentos industriais", 46800),
                    ("Instalações industriais", 6200),
                    ("Veículos e empilhadeiras", 3400),
                    ("Móveis e utensílios", 1150),
                    ("Imobilizado em andamento - linha de usinagem", 2700),
                    ("(-) Depreciação acumulada", -52300),
                ],
                "Intangível": [
                    ("Softwares e licenças de uso", 1900),
                    ("Marcas e patentes", 420),
                    ("(-) Amortização acumulada", -1480),
                ],
            },
            "PC": {
                "Fornecedores": [
                    ("Fornecedores nacionais", 24600),
                    ("Fornecedores estrangeiros", 3900),
                ],
                "Empréstimos e Financiamentos": [
                    ("Empréstimos bancários - capital de giro", 26800),
                    ("Financiamentos - FINAME/BNDES", 4900),
                    ("Empréstimos reclassificados do longo prazo (covenant)", 6700),
                    ("Duplicatas descontadas e antecipação de recebíveis", 9700),
                    ("Conta garantida", 2850),
                ],
                "Arrendamentos": [
                    ("Arrendamentos a pagar - CPC 06 (R2)", 1240),
                ],
                "Obrigações Trabalhistas e Sociais": [
                    ("Salários e ordenados a pagar", 4180),
                    ("Provisão de férias e encargos", 2510),
                    ("Provisão de 13º salário e encargos", 1110),
                    ("INSS a recolher", 2940),
                    ("FGTS a recolher", 780),
                ],
                "Obrigações Tributárias": [
                    ("ICMS a recolher", 1860),
                    ("PIS e COFINS a recolher", 940),
                    ("ISS a recolher", 120),
                    ("IRRF a recolher", 410),
                    ("Parcelamentos tributários - curto prazo", 5600),
                ],
                "Partes Relacionadas": [
                    ("Mútuos a pagar - Vertentes Participações S.A.", 12800),
                ],
                "Outras Obrigações": [
                    ("Adiantamentos de clientes", 1450),
                    ("Provisões trabalhistas e cíveis - curto prazo", 2300),
                    ("Outras contas a pagar", 1180),
                ],
            },
            "PNC": {
                "Empréstimos e Financiamentos": [
                    ("Financiamentos - FINAME/BNDES", 6200),
                ],
                "Obrigações Tributárias": [
                    ("Parcelamentos tributários - longo prazo", 14900),
                ],
                "Provisões": [
                    ("Provisão para contingências trabalhistas", 5100),
                    ("Provisão para contingências tributárias", 2400),
                    ("Provisão para contingências cíveis", 900),
                ],
                "Arrendamentos": [
                    ("Arrendamentos a pagar - CPC 06 (R2)", 3100),
                ],
            },
            "PL": {
                "Capital Social": [
                    ("Capital social subscrito", 45000),
                    ("(-) Capital social a integralizar", -2000),
                ],
                "Reservas": [
                    ("Reserva legal", 1200),
                    ("Ajuste de avaliação patrimonial", 1850),
                ],
                "Resultados Acumulados": "PLUG",  # prejuízos acumulados
            },
        }
    }


def bp_metalurgica_2024():
    """2024: mesma estrutura, empresa ainda respirando (dívida menos concentrada
    no curto prazo, estoque maior, PECLD menor, sem reclassificação de covenant)."""
    return {
        "AC": {
            "Disponível": [
                ("Caixa e bancos conta movimento", 1240),
                ("Aplicações financeiras de liquidez imediata", 3600),
            ],
            "Contas a Receber": [
                ("Duplicatas a receber de clientes - mercado interno", 27900),
                ("Duplicatas a receber de clientes - mercado externo", 4100),
                ("(-) Perdas estimadas em créditos de liquidação duvidosa", -1980),
            ],
            "Estoques": [
                ("Matérias-primas e insumos", 12400),
                ("Produtos em elaboração", 4300),
                ("Produtos acabados", 8100),
                ("Materiais de manutenção e consumo", 910),
                ("(-) Provisão para obsolescência de estoques", -1100),
            ],
            "Tributos a Recuperar": [
                ("ICMS a recuperar", 2180),
                ("PIS e COFINS a recuperar", 1460),
                ("IRRF sobre aplicações financeiras", 340),
            ],
            "Outros Créditos": [
                ("Adiantamentos a fornecedores", 2210),
                ("Adiantamentos a empregados", 390),
                ("Despesas antecipadas - seguros e apólices", 260),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                ("Créditos tributários - ICMS sobre ativo permanente", 3900),
                ("Depósitos judiciais - trabalhistas", 2480),
                ("Depósitos judiciais - tributários", 1610),
                ("Títulos a receber - venda de imobilizado", 940),
            ],
            "Investimentos": [
                ("Participações em outras sociedades - avaliadas ao custo", 180),
            ],
            "Imobilizado": [
                ("Terrenos", 8500),
                ("Edificações e benfeitorias", 24000),
                ("Máquinas, aparelhos e equipamentos industriais", 45200),
                ("Instalações industriais", 6200),
                ("Veículos e empilhadeiras", 3900),
                ("Móveis e utensílios", 1150),
                ("Imobilizado em andamento - linha de usinagem", 1100),
                ("(-) Depreciação acumulada", -46800),
            ],
            "Intangível": [
                ("Softwares e licenças de uso", 1720),
                ("Marcas e patentes", 420),
                ("(-) Amortização acumulada", -1180),
            ],
        },
        "PC": {
            "Fornecedores": [
                ("Fornecedores nacionais", 18300),
                ("Fornecedores estrangeiros", 4600),
            ],
            "Empréstimos e Financiamentos": [
                ("Empréstimos bancários - capital de giro", 19400),
                ("Financiamentos - FINAME/BNDES", 4700),
                ("Duplicatas descontadas e antecipação de recebíveis", 5100),
                ("Conta garantida", 640),
            ],
            "Arrendamentos": [
                ("Arrendamentos a pagar - CPC 06 (R2)", 1180),
            ],
            "Obrigações Trabalhistas e Sociais": [
                ("Salários e ordenados a pagar", 3860),
                ("Provisão de férias e encargos", 2340),
                ("Provisão de 13º salário e encargos", 1040),
                ("INSS a recolher", 1120),
                ("FGTS a recolher", 410),
            ],
            "Obrigações Tributárias": [
                ("ICMS a recolher", 1610),
                ("PIS e COFINS a recolher", 1080),
                ("ISS a recolher", 90),
                ("IRRF a recolher", 380),
                ("Parcelamentos tributários - curto prazo", 4200),
            ],
            "Partes Relacionadas": [
                ("Mútuos a pagar - Vertentes Participações S.A.", 6400),
            ],
            "Outras Obrigações": [
                ("Adiantamentos de clientes", 2740),
                ("Provisões trabalhistas e cíveis - curto prazo", 1400),
                ("Outras contas a pagar", 960),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                ("Financiamentos - FINAME/BNDES", 14800),
            ],
            "Obrigações Tributárias": [
                ("Parcelamentos tributários - longo prazo", 17600),
            ],
            "Provisões": [
                ("Provisão para contingências trabalhistas", 3900),
                ("Provisão para contingências tributárias", 2100),
                ("Provisão para contingências cíveis", 700),
            ],
            "Arrendamentos": [
                ("Arrendamentos a pagar - CPC 06 (R2)", 4050),
            ],
        },
        "PL": {
            "Capital Social": [
                ("Capital social subscrito", 45000),
                ("(-) Capital social a integralizar", -2000),
            ],
            "Reservas": [
                ("Reserva legal", 1200),
                ("Ajuste de avaliação patrimonial", 1850),
            ],
            "Resultados Acumulados": "PLUG",
        },
    }


def bp_componentes(ano):
    """Controlada em situação pior: PASSIVO A DESCOBERTO (PL negativo)."""
    if ano == 2025:
        return {
            "AC": {
                "Disponível": [("Numerário disponível em bancos", 96)],
                "Contas a Receber": [
                    ("Clientes - mercado interno", 6820),
                    ("(-) PECLD", -1640),
                ],
                "Estoques": [
                    ("Matéria-prima", 2140),
                    ("Produtos acabados", 1380),
                    ("(-) Provisão para perdas em estoques", -890),
                ],
                "Tributos a Recuperar": [("ICMS a recuperar", 640), ("PIS/COFINS a compensar", 305)],
                "Outros Créditos": [("Adiantamentos diversos", 218)],
            },
            "ANC": {
                "Realizável a Longo Prazo": [("Depósitos judiciais", 1180)],
                "Imobilizado": [
                    ("Máquinas e equipamentos", 14600),
                    ("Ferramental e moldes", 3900),
                    ("Veículos", 620),
                    ("(-) Depreciação acumulada", -14900),
                ],
                "Intangível": [("Software", 210), ("(-) Amortização acumulada", -150)],
            },
            "PC": {
                "Fornecedores": [("Fornecedores nacionais - em atraso", 11400), ("Fornecedores nacionais - a vencer", 2180)],
                "Empréstimos e Financiamentos": [
                    ("Empréstimos bancários - capital de giro", 8900),
                    ("Antecipação de recebíveis (factoring)", 3100),
                    ("Cheque especial / conta garantida", 1420),
                ],
                "Obrigações Trabalhistas e Sociais": [
                    ("Salários a pagar - em atraso", 2180),
                    ("Provisão de férias e 13º", 1640),
                    ("INSS e FGTS a recolher - em atraso", 3920),
                ],
                "Obrigações Tributárias": [
                    ("ICMS a recolher - em atraso", 2860),
                    ("PIS/COFINS a recolher", 740),
                    ("Parcelamentos tributários - curto prazo", 2100),
                ],
                "Partes Relacionadas": [("Mútuos a pagar - controladora", 9600)],
                "Outras Obrigações": [("Provisões trabalhistas", 3400), ("Outras contas a pagar", 610)],
            },
            "PNC": {
                "Obrigações Tributárias": [("Parcelamentos tributários - longo prazo", 4800)],
                "Provisões": [("Provisão para contingências trabalhistas e cíveis", 6200)],
            },
            "PL": {
                "Capital Social": [("Capital social", 8000)],
                "Resultados Acumulados": "PLUG",  # ficará bem negativo
            },
        }
    return {
        "AC": {
            "Disponível": [("Numerário disponível em bancos", 410)],
            "Contas a Receber": [("Clientes - mercado interno", 9240), ("(-) PECLD", -820)],
            "Estoques": [("Matéria-prima", 3180), ("Produtos acabados", 2260), ("(-) Provisão para perdas em estoques", -340)],
            "Tributos a Recuperar": [("ICMS a recuperar", 520), ("PIS/COFINS a compensar", 410)],
            "Outros Créditos": [("Adiantamentos diversos", 340)],
        },
        "ANC": {
            "Realizável a Longo Prazo": [("Depósitos judiciais", 860)],
            "Imobilizado": [
                ("Máquinas e equipamentos", 14200),
                ("Ferramental e moldes", 3600),
                ("Veículos", 890),
                ("(-) Depreciação acumulada", -13100),
            ],
            "Intangível": [("Software", 210), ("(-) Amortização acumulada", -110)],
        },
        "PC": {
            "Fornecedores": [("Fornecedores nacionais - em atraso", 5900), ("Fornecedores nacionais - a vencer", 3400)],
            "Empréstimos e Financiamentos": [
                ("Empréstimos bancários - capital de giro", 7400),
                ("Antecipação de recebíveis (factoring)", 1600),
                ("Cheque especial / conta garantida", 380),
            ],
            "Obrigações Trabalhistas e Sociais": [
                ("Salários a pagar - em atraso", 980),
                ("Provisão de férias e 13º", 1480),
                ("INSS e FGTS a recolher - em atraso", 1840),
            ],
            "Obrigações Tributárias": [
                ("ICMS a recolher - em atraso", 1240),
                ("PIS/COFINS a recolher", 690),
                ("Parcelamentos tributários - curto prazo", 1700),
            ],
            "Partes Relacionadas": [("Mútuos a pagar - controladora", 4200)],
            "Outras Obrigações": [("Provisões trabalhistas", 1900), ("Outras contas a pagar", 430)],
        },
        "PNC": {
            "Obrigações Tributárias": [("Parcelamentos tributários - longo prazo", 6100)],
            "Provisões": [("Provisão para contingências trabalhistas e cíveis", 4300)],
        },
        "PL": {
            "Capital Social": [("Capital social", 8000)],
            "Resultados Acumulados": "PLUG",
        },
    }


def bp_logistica(ano):
    f = 1.0 if ano == 2025 else 1.12
    r = lambda v: int(round(v * f))
    return {
        "AC": {
            "Disponível": [("Bancos conta movimento", r(320))],
            "Contas a Receber": [("Fretes a receber", r(3180)), ("(-) PECLD", r(-240))],
            "Tributos a Recuperar": [("ISS retido a recuperar", r(96))],
            "Outros Créditos": [("Adiantamentos a motoristas", r(180))],
        },
        "ANC": {
            "Imobilizado": [
                ("Frota de veículos e implementos", r(9800)),
                ("(-) Depreciação acumulada da frota", r(-6100)),
            ],
        },
        "PC": {
            "Fornecedores": [("Fornecedores - combustível e manutenção", r(1840))],
            "Empréstimos e Financiamentos": [("Financiamento de veículos - CDC", r(2600))],
            "Obrigações Trabalhistas e Sociais": [("Salários e encargos", r(940)), ("Provisão de férias e 13º", r(620))],
            "Obrigações Tributárias": [("ISS e tributos a recolher", r(210))],
            "Partes Relacionadas": [("Conta corrente - Vertentes Metalúrgica", r(1400))],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [("Financiamento de veículos - CDC longo prazo", r(1900))],
            "Provisões": [("Provisão para contingências", r(480))],
        },
        "PL": {
            "Capital Social": [("Capital social", 2500)],
            "Resultados Acumulados": "PLUG",
        },
    }


def bp_spe(ano):
    dep = -2600 if ano == 2025 else -2300
    return {
        "AC": {
            "Disponível": [("Caixa", 18)],
            "Outros Créditos": [("Aluguéis a receber - partes relacionadas", 640 if ano == 2025 else 520)],
        },
        "ANC": {
            "Investimentos": [("Propriedades para investimento - galpões locados ao grupo", 31500)],
            "Imobilizado": [("Edificações", 12800), ("(-) Depreciação acumulada", dep)],
        },
        "PC": {
            "Empréstimos e Financiamentos": [("Financiamento imobiliário - parcela circulante", 3100 if ano == 2025 else 2900)],
            "Obrigações Tributárias": [("Tributos sobre locação a recolher", 96)],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [("Financiamento imobiliário - longo prazo", 22400 if ano == 2025 else 25100)],
        },
        "PL": {
            "Capital Social": [("Capital social", 6000)],
            "Resultados Acumulados": "PLUG",
        },
    }


def bp_holding(ano, mep_positivo, provisao_descoberto, mutuos_receber):
    """Holding. MEP: participação × PL da controlada, mas **capado em zero** —
    quando a controlada tem PASSIVO A DESCOBERTO (PL negativo), o investimento
    não vira ativo negativo: para em zero e a parcela negativa é reconhecida
    como `Provisão para passivo a descoberto de controlada` (tratamento usual
    quando a controladora responde pela obrigação). É o caso da Componentes."""
    invest = [(rot, val) for rot, val in mep_positivo if val > 0]
    passivo_desc = [("Provisão para passivo a descoberto de controlada", provisao_descoberto)] if provisao_descoberto else []
    return {
        "AC": {
            "Disponível": [("Caixa e equivalentes de caixa", 210 if ano == 2025 else 880)],
            "Outros Créditos": [("Despesas antecipadas", 40)],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                ("Mútuos a receber de controladas", mutuos_receber),
            ],
            "Investimentos": invest,
        },
        "PC": {
            "Empréstimos e Financiamentos": [("Empréstimo com garantia de recebíveis do grupo", 4200 if ano == 2025 else 1800)],
            "Obrigações Tributárias": [("Tributos a recolher", 74)],
            "Outras Obrigações": [("Honorários da administração a pagar", 320)],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [("Empréstimo de sócios - subordinado", 9800 if ano == 2025 else 5200)],
            "Provisões": passivo_desc,
        },
        "PL": {
            "Capital Social": [("Capital social subscrito e integralizado", 30000)],
            "Resultados Acumulados": "PLUG",
        },
    }
