# -*- coding: utf-8 -*-
"""
Book de teste — GRUPO PIRAQUARA (empresa fictícia, três exercícios, DISTRESS).

É o TERCEIRO book do repositório (fatia F2.4 do roadmap). Os dois primeiros
cobrem a extração fiel (`book-vertentes`) e a dificuldade de formato de um kit
grande (`book-canastra`). Nenhum dos dois tem, como caso CENTRAL, o que um
mandato de reestruturação traz sempre:

  1. **Patrimônio líquido negativo** (passivo a descoberto) na operacional, com
     a holding carregando a provisão correspondente em vez de investimento.
  2. **Covenant financeiro rompido** — Dívida Líquida / EBITDA acima do limite —
     com o cálculo explícito no mapa de dívida e a consequência contábil (a
     dívida de longo prazo desce inteira para o circulante).
  3. **Aging itemizado por NOME** (fornecedor, cliente), sem linha de resto e com
     vencidos acima de 90 dias relevantes — é o formato medido em produção
     (`.claude/memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md`).
  4. **Extrato bancário MENSAL** de uma conta, cujo saldo fecha no caixa do BP.
  5. **DRE com despesa financeira BRUTA**, separada da receita financeira.
  6. **Mútuos entre as entidades**, espelhados nos dois balanços, com juros
     capitalizados que aparecem nas DUAS DREs.

Tudo em R$ MIL, exceto o extrato bancário, que sai em REAIS com centavos (é como
o banco emite — e é a pré-condição de escala exercitada neste book).

O módulo só declara CONTAS-FOLHA e parâmetros. Nenhum subtotal é digitado.

Duas contas NÃO são declaradas aqui, e o porquê é o desenho do book:

  • **Resultados acumulados** — em 2023 é a conta que fecha o balanço de
    abertura; em 2024 e 2025 é o saldo anterior MAIS o resultado da DRE. Não há
    distribuição nem aumento de capital: ΔPL = resultado, sem exceção.
  • **Disponível** — em 2023 é declarado; em 2024 e 2025 é a conta que fecha o
    balanço (o que um modelo de três demonstrações faz). Ele NÃO é uma linha de
    ajuste escondida: a DFC reconstrói a variação dele linha a linha a partir
    das demais contas, sem nenhuma rubrica de "outras variações", e o extrato
    bancário mensal termina nele.
"""

GRUPO = "GRUPO PIRAQUARA"

ANOS = (2023, 2024, 2025)

ENTIDADES = {
    "holding": {
        "razao_social": "PIRAQUARA PARTICIPAÇÕES S.A.",
        "curto": "Piraquara Participações",
        "cnpj": "61.702.330/0001-41",
    },
    "metalurgica": {
        "razao_social": "PIRAQUARA METALÚRGICA E ESTRUTURAS LTDA.",
        "curto": "Piraquara Metalúrgica",
        "cnpj": "61.702.331/0001-96",
    },
    "servicos": {
        "razao_social": "PIRAQUARA MONTAGENS E SERVIÇOS INDUSTRIAIS LTDA.",
        "curto": "Piraquara Montagens",
        "cnpj": "61.702.332/0001-30",
    },
}

ORDEM = ["holding", "metalurgica", "servicos"]
CONTROLADAS = ["metalurgica", "servicos"]
PARTICIPACAO = {"metalurgica": 1.00, "servicos": 1.00}

# Marcadores: o valor desta conta é calculado pelo motor, não declarado.
CAIXA = "CAIXA"          # 2023 declarado em CAIXA_2023; 2024/2025 fecham o balanço
EMPRESTIMOS_CP = "EMP_CP"
EMPRESTIMOS_RECLASS = "EMP_RECLASS"
EMPRESTIMOS_LP = "EMP_LP"
MUTUO = "MUTUO"          # (MUTUO, código do contrato)
MEP = "MEP"
PROVISAO_DESCOBERTO = "PROV_DESC"
PLUG = "PLUG"

CAIXA_2023 = {"holding": 9_460, "metalurgica": 2_937, "servicos": 1_874}

# O rótulo do Disponível. Na Metalúrgica é UMA conta bancária só, de propósito:
# é o que permite o extrato mensal daquela conta fechar no caixa do balanço sem
# rateio nenhum.
ROTULO_CAIXA = {
    "holding": "Caixa e equivalentes de caixa",
    "metalurgica": "Bancos conta movimento - Banco Tapajós S.A. c/c 20.417-3",
    "servicos": "Caixa e bancos",
}


def c(rotulo, **por_ano):
    """Conta-folha. Ano AUSENTE = a conta não existia naquele exercício (célula
    vazia no comparativo), que é diferente de valer zero."""
    return (rotulo, {int(k[1:]): v for k, v in por_ano.items() if v is not None})


# ---------------------------------------------------------------------------
# PIRAQUARA METALÚRGICA — a operacional em distress.
#
# A história: fabricante de estruturas metálicas para galpões e torres. 2023 é
# o último ano normal. Em 2024 o preço do aço sobe sem repasse e a margem
# comprime — o covenant ainda passa, por pouco. Em 2025 a carteira de obras
# encolhe, dois clientes grandes atrasam, a empresa deixa de recolher INSS e
# ICMS para pagar folha, reconhece impairment na linha de perfis pesados, e o
# índice Dívida Líquida/EBITDA explode. O banco declara o vencimento antecipado,
# o PL fica NEGATIVO, e o auditor emite opinião com ressalva e parágrafo de
# incerteza relevante sobre a continuidade.
# ---------------------------------------------------------------------------
def plano_metalurgica():
    return {
        "AC": {
            "Disponível": [(ROTULO_CAIXA["metalurgica"], CAIXA)],
            "Contas a Receber": [
                c("Clientes - duplicatas a receber", a2023=21_486, a2024=21_902, a2025=24_917),
                c("(-) Perdas estimadas em créditos de liquidação duvidosa",
                  a2023=-1_127, a2024=-2_041, a2025=-4_386),
            ],
            "Estoques": [
                c("Matérias-primas - aço, chapas e perfis", a2023=9_874, a2024=9_142, a2025=9_267),
                c("Produtos em elaboração", a2023=3_411, a2024=3_067, a2025=2_887),
                c("Produtos acabados", a2023=5_632, a2024=8_893, a2025=8_948),
                c("(-) Provisão para perdas em estoques", a2023=-312, a2024=-644, a2025=-1_483),
            ],
            "Tributos a Recuperar": [
                c("ICMS e IPI a recuperar", a2023=2_147, a2024=2_633, a2025=3_018),
            ],
            "Outros Créditos": [
                c("Adiantamentos a fornecedores", a2023=863, a2024=541, a2025=212),
                c("Despesas antecipadas", a2023=291, a2024=262, a2025=147),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais trabalhistas", a2023=1_243, a2024=2_266, a2025=3_801),
            ],
            "Imobilizado": [
                c("Terrenos e edificações industriais", a2023=9_800, a2024=9_800, a2025=9_800),
                c("Máquinas e equipamentos", a2023=41_300, a2024=50_657, a2025=51_857),
                c("Veículos e pontes rolantes", a2023=2_480, a2024=2_480, a2025=2_480),
                c("(-) Depreciação acumulada", a2023=-31_704, a2024=-35_813, a2025=-40_246),
                # Nasce em 2025: a linha de perfis pesados parou e o teste de
                # recuperabilidade deu abaixo do contábil.
                c("(-) Perda por redução ao valor recuperável (impairment)", a2025=-7_850),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores nacionais", a2023=11_243, a2024=12_400, a2025=13_954),
                c("Fornecedores estrangeiros", a2023=1_384, a2024=1_121, a2025=946),
            ],
            "Empréstimos e Financiamentos": [
                ("Empréstimos e financiamentos - parcela circulante", EMPRESTIMOS_CP),
                # A reclassificação por quebra de covenant: nasce em 2025.
                ("Empréstimos reclassificados do não circulante - vencimento antecipado (covenant)",
                 EMPRESTIMOS_RECLASS),
            ],
            "Obrigações Trabalhistas": [
                c("Salários e encargos a pagar", a2023=2_342, a2024=2_516, a2025=3_086),
                c("Provisão de férias e 13º salário", a2023=1_861, a2024=1_924, a2025=2_044),
            ],
            "Obrigações Tributárias": [
                c("ICMS e IPI a recolher", a2023=982, a2024=1_120, a2025=1_508),
                c("INSS e FGTS a recolher", a2023=541, a2024=640, a2025=1_076),
                c("Parcelamento de tributos federais - curto prazo", a2025=980),
            ],
            "Outras Obrigações": [
                c("Adiantamentos de clientes", a2023=1_421, a2024=983, a2025=212),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                ("Empréstimos e financiamentos - não circulante", EMPRESTIMOS_LP),
            ],
            "Partes Relacionadas": [
                ("Mútuo a pagar - Piraquara Participações S.A.", (MUTUO, "MUT-01/2021")),
                ("Mútuo a pagar - Piraquara Montagens e Serviços", (MUTUO, "MUT-02/2024")),
            ],
            "Obrigações Tributárias": [
                c("Parcelamento de tributos federais - longo prazo", a2025=2_970),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2023=1_683, a2024=2_342, a2025=3_912),
                c("Provisão para contingências tributárias", a2023=720, a2024=720, a2025=1_450),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social integralizado", a2023=16_000, a2024=16_000, a2025=16_000),
            ],
            "Lucros ou Prejuízos Acumulados": PLUG,
        },
    }


# ---------------------------------------------------------------------------
# PIRAQUARA MONTAGENS — a irmã saudável. Presta serviço de montagem em campo,
# gera caixa e EMPRESTA para a Metalúrgica a partir de 2024 (mútuo ascendente
# entre irmãs, que é o que acontece quando o banco fecha a porta).
# ---------------------------------------------------------------------------
def plano_servicos():
    return {
        "AC": {
            "Disponível": [(ROTULO_CAIXA["servicos"], CAIXA)],
            "Contas a Receber": [
                c("Clientes - medições a receber", a2023=6_423, a2024=6_981, a2025=7_314),
            ],
            "Outros Créditos": [
                c("Adiantamentos a empregados e viagens", a2023=212, a2024=183, a2025=164),
            ],
        },
        "ANC": {
            "Créditos com Partes Relacionadas": [
                ("Mútuo a receber - Piraquara Metalúrgica", (MUTUO, "MUT-02/2024")),
            ],
            "Imobilizado": [
                c("Guindastes, andaimes e equipamentos de montagem",
                  a2023=5_904, a2024=6_412, a2025=6_412),
                c("(-) Depreciação acumulada", a2023=-2_306, a2024=-2_987, a2025=-3_693),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores e subempreiteiros", a2023=1_142, a2024=1_283, a2025=1_411),
            ],
            "Obrigações Trabalhistas": [
                c("Salários e encargos a pagar", a2023=1_624, a2024=1_742, a2025=1_853),
            ],
            "Obrigações Tributárias": [
                c("ISS, PIS e COFINS a recolher", a2023=613, a2024=662, a2025=721),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Financiamento de equipamentos (FINAME)", a2023=2_100, a2024=1_700, a2025=1_300),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social integralizado", a2023=5_000, a2024=5_000, a2025=5_000),
            ],
            "Lucros ou Prejuízos Acumulados": PLUG,
        },
    }


# ---------------------------------------------------------------------------
# PIRAQUARA PARTICIPAÇÕES — holding pura. Ativo: caixa, mútuo a receber e MEP.
# Quando o PL da Metalúrgica fica negativo, o investimento vai a ZERO e o
# excedente vira provisão para passivo a descoberto no passivo não circulante.
# ---------------------------------------------------------------------------
def plano_holding():
    return {
        "AC": {
            "Disponível": [(ROTULO_CAIXA["holding"], CAIXA)],
        },
        "ANC": {
            "Créditos com Partes Relacionadas": [
                ("Mútuo a receber - Piraquara Metalúrgica", (MUTUO, "MUT-01/2021")),
            ],
            "Investimentos": [
                ("Participação em Piraquara Metalúrgica e Estruturas Ltda. (100%) - MEP",
                 (MEP, "metalurgica")),
                ("Participação em Piraquara Montagens e Serviços Industriais Ltda. (100%) - MEP",
                 (MEP, "servicos")),
            ],
        },
        "PC": {
            "Outras Obrigações": [
                c("Honorários da administração a pagar", a2023=118, a2024=131, a2025=142),
            ],
        },
        "PNC": {
            "Provisões": [
                ("Provisão para passivo a descoberto em controlada", (PROVISAO_DESCOBERTO, "metalurgica")),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social subscrito e integralizado", a2023=34_000, a2024=34_000, a2025=34_000),
            ],
            "Lucros ou Prejuízos Acumulados": PLUG,
        },
    }


PLANOS = {"holding": plano_holding, "metalurgica": plano_metalurgica, "servicos": plano_servicos}


# ---------------------------------------------------------------------------
# CONTRATOS DE DÍVIDA BANCÁRIA DA METALÚRGICA (R$ mil).
#
# O saldo de cada contrato por exercício é o DADO; as contas de empréstimo do
# balanço são a soma deles (circulante pela fração `cp`, o resto no não
# circulante). Em 2025 a quebra do covenant antecipa o vencimento de TUDO: a
# fração que já era circulante fica na linha circulante e o resto desce para a
# linha "reclassificados", que é como o balanço real mostra.
#
# `taxa_efetiva` é o custo anual efetivo usado para os juros do exercício sobre
# o saldo MÉDIO — a soma dos juros é a linha de juros da DRE, ao centavo do mil.
# ---------------------------------------------------------------------------
CONTRATOS = [
    # contrato, credor, modalidade, indexador contratual, taxa efetiva a.a., cp,
    # garantia, saldos {ano}
    dict(contrato="CG-0419/2022", credor="Banco Tapajós S.A.", modalidade="Capital de giro",
         taxa="CDI + 5,20% a.a.", taxa_efetiva={2023: .1846, 2024: .1622, 2025: .1911},
         cp=.40, garantia="Aval dos sócios + cessão de recebíveis", covenant=True,
         saldos={2023: 9_600, 2024: 11_200, 2025: 7_700}),
    dict(contrato="CGA-0088/2024", credor="Banco Tapajós S.A.", modalidade="Conta garantida",
         taxa="CDI + 9,50% a.a.", taxa_efetiva={2024: .2138, 2025: .2412},
         cp=1.0, garantia="Aval dos sócios", covenant=True,
         saldos={2024: 1_850, 2025: 3_940}),
    dict(contrato="CG-7731/2023", credor="Banco Cordilheira S.A.", modalidade="Capital de giro",
         taxa="CDI + 4,60% a.a.", taxa_efetiva={2023: .1781, 2024: .1557, 2025: .1846},
         cp=.35, garantia="Alienação fiduciária de imóvel", covenant=True,
         saldos={2023: 7_200, 2024: 6_400, 2025: 5_600}),
    dict(contrato="FIN-2021-0457", credor="Agência de Fomento do Planalto S.A.",
         modalidade="Financiamento de máquinas", taxa="TLP + 3,40% a.a.",
         taxa_efetiva={2023: .1094, 2024: .1072, 2025: .1118},
         cp=.22, garantia="Alienação fiduciária dos bens", covenant=False,
         saldos={2023: 8_400, 2024: 6_900, 2025: 5_400}),
    dict(contrato="DD-2024-0112", credor="Banco Litoral Sul S.A.", modalidade="Desconto de duplicatas",
         taxa="2,90% a.m.", taxa_efetiva={2024: .4092, 2025: .4092},
         cp=1.0, garantia="Coobrigação sobre duplicatas", covenant=False,
         saldos={2024: 1_200, 2025: 1_300}),
    dict(contrato="CCB-2020-3319", credor="Banco Cordilheira S.A.", modalidade="Cédula de crédito bancário",
         taxa="CDI + 3,90% a.a.", taxa_efetiva={2023: .1703, 2024: .1486, 2025: .1771},
         cp=.40, garantia="Aval dos sócios", covenant=True,
         saldos={2023: 4_900, 2024: 3_500, 2025: 2_100}),
]

# Saldo dos contratos em 31/12/2022 — só para o saldo MÉDIO de 2023. É
# DECLARADO (o book não tem balanço de 2022), e fica explícito para ninguém
# confundir "medido no balanço" com "afirmado pela empresa".
SALDO_2022 = {"CG-0419/2022": 8_800, "CG-7731/2023": 0, "FIN-2021-0457": 9_900,
              "CCB-2020-3319": 6_300}

# O covenant, como está no contrato CG-0419/2022 (e cruzado nos demais marcados
# `covenant=True`). EBITDA = resultado operacional antes do resultado financeiro
# + depreciação e amortização + impairment (item não caixa, excluído por
# definição contratual). Dívida líquida = dívida BANCÁRIA − disponível; mútuos
# com partes relacionadas NÃO entram (cláusula 7.3) — uma armadilha real.
COVENANT_LIMITE = 3.0


# ---------------------------------------------------------------------------
# MÚTUOS INTRAGRUPO (R$ mil). Juros capitalizados ao saldo, sobre o saldo de
# ABERTURA do exercício; captação do ano não rende no próprio ano. Cada contrato
# aparece nos DOIS balanços (mutuante no ativo, mutuária no passivo) e nas DUAS
# DREs (receita numa, despesa na outra) — com o mesmo número.
# ---------------------------------------------------------------------------
CDI = {2023: .1304, 2024: .1088, 2025: .1362}
MUTUOS = [
    dict(contrato="MUT-01/2021", mutuante="holding", mutuaria="metalurgica",
         remuneracao="100% do CDI", fator_cdi=1.00,
         saldo_2022=4_780, captacoes={2023: 0, 2024: 2_000, 2025: 2_000}),
    dict(contrato="MUT-02/2024", mutuante="servicos", mutuaria="metalurgica",
         remuneracao="105% do CDI", fator_cdi=1.05,
         saldo_2022=0, captacoes={2023: 0, 2024: 1_000, 2025: 1_000}),
]


# ---------------------------------------------------------------------------
# PARÂMETROS DAS DREs. Receita não é saldo, então é a única série "de fora" do
# balanço; o resto desce dela ou é LIDO do balanço (depreciação, PECLD,
# provisões, impairment = variação da conta correspondente).
# ---------------------------------------------------------------------------
RECEITA_BRUTA_MET = {2023: 148_600, 2024: 131_200, 2025: 112_400}
MIX_MET = {
    # fração da receita líquida
    2023: dict(cpv=.735, vendas=.052, ga=.061),
    2024: dict(cpv=.762, vendas=.052, ga=.060),
    2025: dict(cpv=.800, vendas=.050, ga=.058),
}
# Variações de 2023 são DECLARADAS (não há balanço de 2022 no book).
VARIACOES_2023_MET = {"depreciacao": 4_052, "pecld": 381, "estoques": 94,
                      "contingencias": 262, "impairment": 0}
FIN_MET = {
    "multas": {2023: 41, 2024: 183, 2025: 1_264},      # juros e multas moratórias
    "tarifas": {2023: 212, 2024: 263, 2025: 391},      # IOF, tarifas, fiança bancária
    "rendimentos": {2023: 312, 2024: 96, 2025: 18},    # aplicações financeiras
    "descontos": {2023: 121, 2024: 64, 2025: 27},      # descontos obtidos
}
ALIQUOTA_IR = 0.34

RECEITA_BRUTA_SERV = {2023: 31_400, 2024: 33_800, 2025: 34_900}
MIX_SERV = {2023: dict(custo=.712, adm=.089), 2024: dict(custo=.718, adm=.091),
            2025: dict(custo=.731, adm=.093)}
DEPRECIACAO_2023_SERV = 642
TAXA_FINAME_SERV = .1210

DESPESAS_HOLDING = {2023: 478, 2024: 506, 2025: 531}
