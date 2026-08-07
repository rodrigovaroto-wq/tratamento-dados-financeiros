# -*- coding: utf-8 -*-
"""
Book de teste — GRUPO CANASTRA (empresa fictícia, três exercícios).

É o SEGUNDO book do repositório, e existe porque o primeiro (`book-vertentes`)
é fácil demais em três dimensões que a produção não é:

  1. **Dois exercícios.** Com 2023, 2024 e 2025 o comparativo tem três colunas,
     a série do modelo tem três pontos realizados (não dois), e uma conta pode
     NASCER ou MORRER no meio do histórico — que é a forma como distress
     aparece de verdade num plano de contas (antecipação de recebíveis que não
     existia, parcelamento que nasce em 2025, reserva que some).
  2. **Cinco empresas com plano de contas parecido.** Aqui são SEIS, incluindo
     uma que fatura para as outras (verticalização) e uma com participação
     parcial (não controladores), e cada uma nomeia as mesmas contas do seu
     jeito — que é a razão de existir a classificação canônica.
  3. **Um kit de demonstrações.** Um mandato real chega com o que a empresa TEM:
     aging de recebíveis e de pagáveis, posição de estoques com quantidade,
     situação fiscal com parcelamento, contingências por prognóstico, folha,
     composição do imobilizado, extratos, certidões, contrato social,
     organograma, razão analítico. Esses documentos não são "extras": são onde
     moram as contas que o modelo projeta e onde as escalas divergem.

Tudo em R$ MIL, exceto onde explicitado (o mapa de dívida e o faturamento saem
em R$ unidades, os estoques trazem QUANTIDADE junto do valor, e uma tranche de
dívida é em DÓLAR — as três coisas de propósito, para exercitar a pré-condição
de escala e a de moeda).

O módulo só declara CONTAS-FOLHA. Nenhum subtotal é digitado: quem soma é o
`motor.py`, que também valida por `assert` que tudo fecha.
"""

GRUPO = "GRUPO CANASTRA"

# Os três exercícios. A ordem é a cronológica — vários documentos dependem dela.
ANOS = (2023, 2024, 2025)

ENTIDADES = {
    "holding": {
        "razao_social": "CANASTRA PARTICIPAÇÕES S.A.",
        "nome_fantasia": "Canastra Participações",
        "cnpj": "44.555.666/0001-12",
        # Cada empresa nomeia o disponível do seu jeito — de propósito.
        "rotulo_caixa": "Caixa e Equivalentes de Caixa",
    },
    "industria": {
        "razao_social": "CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.",
        "nome_fantasia": "Canastra Embalagens",
        "cnpj": "44.555.667/0001-59",
        "rotulo_caixa": "Disponibilidades",
    },
    "comercial": {
        "razao_social": "CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.",
        "nome_fantasia": "Canastra Distribuidora",
        "cnpj": "44.555.668/0001-01",
        "rotulo_caixa": "Numerário Disponível",
    },
    "transportes": {
        "razao_social": "CN TRANSPORTES E LOGÍSTICA LTDA.",
        "nome_fantasia": "CN Log",
        "cnpj": "44.555.669/0001-46",
        "rotulo_caixa": "Bancos Conta Movimento",
    },
    "agro": {
        "razao_social": "CANASTRA AGROFLORESTAL LTDA.",
        "nome_fantasia": "Canastra Florestal",
        "cnpj": "44.555.670/0001-70",
        "rotulo_caixa": "Caixa e Bancos",
    },
    "imob": {
        "razao_social": "CANASTRA IMOBILIÁRIA SPE LTDA.",
        "nome_fantasia": "Canastra SPE",
        "cnpj": "44.555.671/0001-14",
        "rotulo_caixa": "Caixa",
    },
}

# Participação da holding em cada controlada. A CN Transportes tem sócio
# minoritário (35%) — é o que faz existir participação de não controladores no
# combinado, e o que quebra a leitura ingênua "combinado = soma das colunas".
PARTICIPACAO = {"industria": 1.00, "comercial": 1.00, "transportes": 0.65,
                "agro": 1.00, "imob": 1.00}


# ---------------------------------------------------------------------------
# Uma conta-folha por linha. `c()` recebe o rótulo e os valores por exercício.
#
# Ano AUSENTE significa que a conta NÃO EXISTIA naquele exercício — não que
# valia zero. A distinção é o ponto: no comparativo, a coluna do ano em que a
# conta não existe fica VAZIA, e um extrator que preencher zero ali está
# afirmando algo sobre o negócio que o documento não diz.
#
# O rótulo pode ser um dict {ano: texto} quando a grafia MUDA entre exercícios.
# Isso não é capricho: contabilidade real renomeia conta na virada do plano, e o
# mesmo saldo aparece com dois nomes em dois documentos do mesmo caso.
# ---------------------------------------------------------------------------
def c(rotulo, **por_ano):
    valores = {int(k[1:]): v for k, v in por_ano.items() if v is not None}
    return (rotulo, valores)


def rotulo_do_ano(rotulo, ano):
    if isinstance(rotulo, dict):
        # Vale o rótulo do ano; não havendo, o do ano mais próximo para trás.
        for a in sorted(rotulo, reverse=True):
            if a <= ano:
                return rotulo[a]
        return rotulo[min(rotulo)]
    return rotulo


# ---------------------------------------------------------------------------
# CANASTRA INDÚSTRIA — a operacional principal, plano de contas detalhado.
#
# A história em três exercícios: 2023 é o ano bom (contrato com a cliente
# âncora, margem de 24%); em 2024 a âncora leva a conta para um concorrente e o
# papel kraft encarece; em 2025 a empresa opera com capital de terceiros, quebra
# o covenant de cobertura de juros, adere à transação tributária e passa a
# antecipar recebíveis para fechar o mês.
# ---------------------------------------------------------------------------
def plano_industria():
    return {
        "AC": {
            "Disponível": [
                c("Caixa e bancos conta movimento", a2023=2870, a2024=1420, a2025=610),
                c("Aplicações financeiras de liquidez imediata", a2023=6400, a2024=2100, a2025=180),
                c("Numerário em trânsito", a2023=140, a2024=95, a2025=38),
            ],
            "Contas a Receber": [
                c({2023: "Duplicatas a receber de clientes - mercado interno",
                   2025: "Clientes - duplicatas a receber - mercado interno"},
                  a2023=34900, a2024=31200, a2025=24700),
                c("Duplicatas a receber de clientes - mercado externo",
                  a2023=6400, a2024=5100, a2025=3860),
                # A antecipação de recebíveis NÃO EXISTIA em 2023. Ela nasce como
                # redutora do ativo em 2024 e dobra em 2025 — é o sinal clássico
                # de aperto de caixa, e um comparativo com célula vazia em 2023.
                c("(-) Duplicatas descontadas / antecipação de recebíveis",
                  a2024=-4800, a2025=-9700),
                c("(-) Perdas estimadas em créditos de liquidação duvidosa",
                  a2023=-1900, a2024=-3400, a2025=-6250),
            ],
            "Estoques": [
                c("Matérias-primas - papel kraft e aparas", a2023=12600, a2024=11800, a2025=8900),
                c("Produtos em elaboração", a2023=4300, a2024=3600, a2025=2740),
                c("Produtos acabados", a2023=8900, a2024=7400, a2025=6100),
                c("Materiais de embalagem, manutenção e consumo", a2023=1650, a2024=1380, a2025=980),
                c("Importações em andamento", a2023=2100, a2024=880, a2025=None),
                c("(-) Provisão para obsolescência de estoques", a2023=-980, a2024=-1750, a2025=-3120),
            ],
            "Tributos a Recuperar": [
                c("ICMS a recuperar", a2023=3100, a2024=3480, a2025=4260),
                c("PIS e COFINS a recuperar", a2023=1420, a2024=1690, a2025=2140),
                c("IRPJ e CSLL - antecipações do exercício", a2023=2600, a2024=740, a2025=None),
                c("IRRF sobre aplicações financeiras", a2023=280, a2024=110, a2025=24),
                # Crédito presumido só aparece em 2025 (adesão a regime estadual).
                c("Crédito presumido de ICMS - regime especial", a2025=1180),
            ],
            "Outros Créditos": [
                # Contrapartes intragrupo: existem dos DOIS lados de propósito.
                # Eliminação do combinado que só tem uma perna não fecha, e um
                # book que "fecha" só porque a outra perna não foi escrita é
                # exatamente o teste fácil que este book veio substituir.
                c("Contas a receber intragrupo - Canastra Comercial",
                  a2023=3400, a2024=4100, a2025=5200),
                c("Adiantamentos a fornecedores", a2023=2400, a2024=1900, a2025=1120),
                c("Adiantamentos a empregados", a2023=520, a2024=610, a2025=690),
                c("Despesas antecipadas - seguros e apólices", a2023=380, a2024=340, a2025=210),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Créditos tributários - ICMS sobre ativo permanente",
                  a2023=2900, a2024=3400, a2025=3900),
                c("Depósitos judiciais - trabalhistas", a2023=1800, a2024=2600, a2025=4100),
                c("Depósitos judiciais - tributários", a2023=2200, a2024=2200, a2025=2200),
                c("Títulos a receber - venda de imobilizado", a2023=None, a2024=1400, a2025=900),
                # Ativo fiscal diferido sobre prejuízo fiscal: nasce quando começa
                # a haver prejuízo fiscal para diferir.
                c("Tributos diferidos ativos sobre prejuízo fiscal", a2025=3600),
            ],
            "Investimentos": [
                c("Participações em outras sociedades - avaliadas ao custo",
                  a2023=240, a2024=240, a2025=240),
            ],
            "Imobilizado": [
                c("Terrenos", a2023=11200, a2024=11200, a2025=11200),
                c("Edificações e benfeitorias", a2023=32600, a2024=32600, a2025=32600),
                c("Máquinas, aparelhos e equipamentos industriais",
                  a2023=68400, a2024=71900, a2025=72300),
                c("Instalações industriais", a2023=8900, a2024=9400, a2025=9400),
                c("Veículos e empilhadeiras", a2023=4600, a2024=4600, a2025=3900),
                c("Móveis e utensílios", a2023=1480, a2024=1520, a2025=1520),
                c("Imobilizado em andamento - linha de conversão de chapas",
                  a2023=4200, a2024=2100, a2025=2100),
                # Direito de uso (arrendamento) entra no plano em 2024.
                c("Direito de uso - arrendamentos", a2024=7800, a2025=7800),
                c("(-) Depreciação acumulada", a2023=-49000, a2024=-55000, a2025=-60000),
                c("(-) Amortização acumulada do direito de uso", a2024=-1560, a2025=-3120),
            ],
            "Intangível": [
                c("Softwares e licenças de uso", a2023=2600, a2024=3100, a2025=3100),
                c("Marcas e patentes", a2023=520, a2024=520, a2025=520),
                c("(-) Amortização acumulada", a2023=-1400, a2024=-1900, a2025=-2380),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores nacionais", a2023=14600, a2024=17900, a2025=17900),
                c("Fornecedores estrangeiros", a2023=3200, a2024=2400, a2025=1900),
                # Título em atraso é conta separada a partir de 2025 (o
                # departamento passou a segregar) — mesma natureza, rótulo novo.
                c("Fornecedores - títulos vencidos e não pagos", a2025=5900),
                c("Fornecedores intragrupo - Canastra Agroflorestal",
                  a2023=1900, a2024=2300, a2025=2900),
            ],
            "Empréstimos e Financiamentos": [
                c("Capital de giro - instituições financeiras", a2023=9800, a2024=15400, a2025=12400),
                c("FINAME - financiamento de máquinas", a2023=4200, a2024=4200, a2025=3400),
                c("Conta garantida / cheque especial", a2023=None, a2024=2600, a2025=4200),
                c("Operações de antecipação de recebíveis", a2023=None, a2024=4800, a2025=9700),
                # A reclassificação por quebra de covenant: o saldo estava no
                # não circulante e desce inteiro para o circulante em 2025.
                c("Financiamentos reclassificados por quebra de cláusula restritiva", a2025=14900),
            ],
            "Arrendamentos": [
                c("Arrendamentos a pagar - circulante", a2024=1620, a2025=1780),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários e ordenados a pagar", a2023=2400, a2024=2600, a2025=3100),
                c("INSS a recolher", a2023=980, a2024=1100, a2025=1840),
                c("FGTS a recolher", a2023=410, a2024=460, a2025=720),
                c("Provisão de férias e encargos", a2023=3100, a2024=3300, a2025=3600),
                c("Provisão de 13º salário e encargos", a2023=1400, a2024=1500, a2025=1620),
                c("Rescisões contratuais a pagar", a2025=1800),
            ],
            "Obrigações Tributárias": [
                c("ICMS a recolher", a2023=1900, a2024=2100, a2025=2600),
                c("PIS e COFINS a recolher", a2023=840, a2024=960, a2025=1180),
                c("IRRF sobre folha a recolher", a2023=390, a2024=420, a2025=510),
                c("ISS a recolher", a2023=110, a2024=120, a2025=140),
                # O parcelamento tributário nasce em 2025 (adesão à transação).
                c("Parcelamento - transação tributária federal (curto prazo)", a2025=3400),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - Canastra Participações", a2023=4200, a2024=9800, a2025=11400),
            ],
            "Outras Obrigações": [
                c("Aluguéis a pagar - Canastra Imobiliária SPE", a2023=720, a2024=780, a2025=940),
                c("Conta corrente a pagar - CN Transportes e Logística",
                  a2023=1100, a2024=1400, a2025=1900),
                c("Adiantamentos de clientes", a2023=1900, a2024=1400, a2025=860),
                c("Comissões sobre vendas a pagar", a2023=680, a2024=540, a2025=390),
                c("Outras contas a pagar", a2023=920, a2024=1100, a2025=1340),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2023=26400, a2024=22800, a2025=3200),
                c("FINAME - longo prazo", a2023=12600, a2024=8400, a2025=4200),
            ],
            "Arrendamentos": [
                c("Arrendamentos a pagar - não circulante", a2024=4900, a2025=3300),
            ],
            "Obrigações Tributárias": [
                c("Parcelamento - transação tributária federal (longo prazo)", a2025=9900),
                c("REFIS - saldo remanescente", a2023=3900, a2024=2900, a2025=1900),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2023=2100, a2024=3400, a2025=4200),
                c("Provisão para contingências tributárias", a2023=1600, a2024=1600, a2025=1900),
                c("Provisão para contingências cíveis", a2023=400, a2024=700, a2025=900),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social subscrito e integralizado", a2023=40000, a2024=40000, a2025=40000),
            ],
            "Reservas de Lucros": [
                c("Reserva legal", a2023=4200, a2024=4200, a2025=4200),
                # A reserva de lucros a realizar é consumida em 2024.
                c("Reserva de lucros a realizar", a2023=6800),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ---------------------------------------------------------------------------
# CANASTRA COMERCIAL — distribuidora. Plano enxuto, sem imobilizado relevante,
# e é ela que entra em PASSIVO A DESCOBERTO em 2025.
# ---------------------------------------------------------------------------
def plano_comercial():
    return {
        "AC": {
            "Disponível": [
                c("Numerário disponível em caixa e bancos", a2023=1100, a2024=430, a2025=95),
            ],
            "Créditos": [
                c("Clientes - mercado interno", a2023=12400, a2024=10600, a2025=8900),
                c("(-) Provisão para créditos de liquidação duvidosa",
                  a2023=-620, a2024=-1300, a2025=-2400),
                c("Cartões de crédito a receber", a2023=1800, a2024=1600, a2025=1300),
            ],
            "Mercadorias": [
                c("Mercadorias para revenda", a2023=9800, a2024=8600, a2025=6900),
                c("Mercadorias em poder de terceiros", a2023=640, a2024=520, a2025=380),
            ],
            "Impostos a Recuperar": [
                c("ICMS sobre compras a recuperar", a2023=1200, a2024=1340, a2025=1580),
                c("PIS/COFINS não cumulativo a recuperar", a2023=560, a2024=640, a2025=790),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais", a2023=340, a2024=520, a2025=820),
            ],
            "Imobilizado": [
                c("Móveis, utensílios e instalações", a2023=1900, a2024=1900, a2025=1900),
                c("Veículos de entrega", a2023=2400, a2024=2400, a2025=1600),
                c("(-) Depreciações acumuladas", a2023=-2100, a2024=-2700, a2025=-2900),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores nacionais", a2023=9600, a2024=10400, a2025=11900),
                c("Fornecedores intragrupo - Canastra Indústria",
                  a2023=3400, a2024=4100, a2025=5200),
            ],
            "Empréstimos": [
                c("Capital de giro", a2023=3800, a2024=4900, a2025=6400),
                c("Antecipação de recebíveis de cartão", a2024=1400, a2025=2600),
            ],
            "Obrigações Trabalhistas": [
                c("Salários, férias e encargos a pagar", a2023=1400, a2024=1500, a2025=1700),
            ],
            "Obrigações Tributárias": [
                c("ICMS a recolher", a2023=760, a2024=840, a2025=980),
                c("Simples/PIS/COFINS a recolher", a2023=340, a2024=390, a2025=460),
                c("Parcelamento de ICMS estadual", a2024=1400, a2025=2400),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - Canastra Participações", a2023=1800, a2024=2900, a2025=4900),
            ],
        },
        "PNC": {
            "Empréstimos": [
                c("Capital de giro - longo prazo", a2023=2400, a2024=1600, a2025=600),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas e cíveis",
                  a2023=380, a2024=760, a2025=1400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social integralizado", a2023=6000, a2024=6000, a2025=6000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ---------------------------------------------------------------------------
# CN TRANSPORTES — 65% da holding. Frota própria, plano pequeno.
# ---------------------------------------------------------------------------
def plano_transportes():
    return {
        "AC": {
            "Disponível": [
                c("Bancos conta movimento", a2023=680, a2024=310, a2025=88),
            ],
            "Contas a Receber": [
                c("Fretes a faturar e a receber", a2023=4200, a2024=3800, a2025=3100),
                c("Conta corrente a receber - Canastra Indústria",
                  a2023=1100, a2024=1400, a2025=1900),
            ],
            "Outros Créditos": [
                c("Adiantamentos a motoristas e agregados", a2023=290, a2024=340, a2025=410),
                c("Créditos de ICMS sobre combustível", a2023=180, a2024=210, a2025=260),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Veículos, cavalos mecânicos e carretas", a2023=14600, a2024=14600, a2025=12800),
                c("Equipamentos de rastreamento e telemetria", a2023=680, a2024=740, a2025=740),
                c("(-) Depreciação acumulada", a2023=-7900, a2024=-9600, a2025=-10400),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores - combustível, pneus e manutenção",
                  a2023=2100, a2024=2600, a2025=3400),
            ],
            "Empréstimos": [
                c("FINAME - frota", a2023=2600, a2024=2600, a2025=2600),
                c("Capital de giro", a2023=900, a2024=1900, a2025=3100),
            ],
            "Obrigações Trabalhistas": [
                c("Salários, férias e encargos a pagar", a2023=1200, a2024=1300, a2025=1500),
            ],
            "Obrigações Tributárias": [
                c("ISS e ICMS sobre serviços de transporte a recolher",
                  a2023=210, a2024=260, a2025=340),
            ],
        },
        "PNC": {
            "Empréstimos": [
                c("FINAME - longo prazo", a2023=5200, a2024=3900, a2025=2600),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2023=420, a2024=780, a2025=1300),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2023=3000, a2024=3000, a2025=3000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ---------------------------------------------------------------------------
# CANASTRA AGROFLORESTAL — floresta plantada (ativo biológico) e madeira.
# Fornece matéria-prima para a Indústria: é a contraparte intragrupo do
# faturamento entre empresas.
# ---------------------------------------------------------------------------
def plano_agro():
    return {
        "AC": {
            "Disponível": [
                c("Caixa e bancos", a2023=420, a2024=380, a2025=260),
            ],
            "Contas a Receber": [
                c("Clientes - madeira e resíduos", a2023=1900, a2024=1700, a2025=1400),
                c("Contas a receber intragrupo - Canastra Indústria",
                  a2023=1900, a2024=2300, a2025=2900),
            ],
            "Estoques": [
                c("Madeira colhida e resíduos em pátio", a2023=2600, a2024=2400, a2025=2100),
            ],
        },
        "ANC": {
            "Ativos Biológicos": [
                c("Florestas plantadas - eucalipto (valor justo)",
                  a2023=18400, a2024=17200, a2025=15900),
            ],
            "Imobilizado": [
                c("Terras e benfeitorias rurais", a2023=9600, a2024=9600, a2025=9600),
                c("Máquinas e implementos agrícolas", a2023=3400, a2024=3400, a2025=3400),
                c("(-) Depreciação acumulada", a2023=-1900, a2024=-2400, a2025=-2900),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores e prestadores rurais", a2023=1400, a2024=1600, a2025=1900),
            ],
            "Empréstimos": [
                c("Crédito rural - custeio", a2023=2900, a2024=3400, a2025=4100),
            ],
            "Obrigações Trabalhistas": [
                c("Salários e encargos rurais a pagar", a2023=640, a2024=690, a2025=780),
            ],
        },
        "PNC": {
            "Empréstimos": [
                c("Crédito rural - investimento (longo prazo)", a2023=8400, a2024=7600, a2025=6900),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2023=8000, a2024=8000, a2025=8000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ---------------------------------------------------------------------------
# CANASTRA IMOBILIÁRIA SPE — os imóveis do grupo. É ela que sustenta o
# patrimônio combinado, e é a única que usa "Propriedades para investimento"
# (Investimentos, não Imobilizado — a distinção que o classificador tem de fazer).
# ---------------------------------------------------------------------------
def plano_imob():
    return {
        "AC": {
            "Disponível": [
                c("Caixa", a2023=180, a2024=210, a2025=240),
            ],
            "Contas a Receber": [
                c("Aluguéis a receber - Canastra Indústria", a2023=720, a2024=780, a2025=940),
                c("Aluguéis a receber - terceiros", a2023=340, a2024=380, a2025=420),
            ],
        },
        "ANC": {
            "Investimentos": [
                c("Propriedades para investimento - galpões industriais",
                  a2023=28600, a2024=28600, a2025=28600),
                c("Propriedades para investimento - terrenos", a2023=6400, a2024=6400, a2025=6400),
                c("(-) Depreciação de propriedades para investimento",
                  a2023=-4200, a2024=-4900, a2025=-5600),
            ],
        },
        "PC": {
            "Obrigações Tributárias": [
                c("IPTU e taxas a recolher", a2023=180, a2024=210, a2025=240),
            ],
            "Empréstimos": [
                c("Financiamento imobiliário - curto prazo", a2023=1900, a2024=1900, a2025=1900),
            ],
        },
        "PNC": {
            "Empréstimos": [
                c("Financiamento imobiliário - longo prazo", a2023=9600, a2024=7700, a2025=5800),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2023=12000, a2024=12000, a2025=12000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ---------------------------------------------------------------------------
# CANASTRA PARTICIPAÇÕES — holding pura. O ativo dela é MEP; o passivo, os
# mútuos que ela financiou nas controladas e o empréstimo dos sócios.
#
# `mep_positivo` e `provisao` chegam CALCULADOS do motor (a partir do PL real já
# calibrado das controladas), e `mutuos` é o espelho do que as controladas
# declaram dever — é assim que as eliminações do combinado fecham sem número
# digitado à mão.
# ---------------------------------------------------------------------------
def plano_holding(ano, mep_positivo, provisao, mutuos):
    caixa = {2023: 3400, 2024: 1900, 2025: 620}[ano]
    aporte = {2023: 0, 2024: 6000, 2025: 14000}[ano]
    plano = {
        "AC": {
            "Disponível": [("Caixa e equivalentes de caixa", {ano: caixa})],
            "Créditos com Partes Relacionadas": [
                ("Mútuos a receber de controladas", {ano: mutuos}),
            ],
        },
        "ANC": {
            "Investimentos": [(rot, {ano: v}) for rot, v in mep_positivo],
        },
        "PC": {
            "Outras Obrigações": [
                ("Dividendos a pagar", {ano: {2023: 2400, 2024: 0, 2025: 0}[ano]}),
                ("Honorários da administração a pagar", {ano: {2023: 340, 2024: 380, 2025: 420}[ano]}),
            ],
        },
        "PNC": {
            "Partes Relacionadas": [
                ("Empréstimo de sócios (mútuo com quotistas)", {ano: aporte}) if aporte else None,
            ],
            "Provisões": [
                ("Provisão para passivo a descoberto em controladas", {ano: provisao}) if provisao else None,
            ],
        },
        "PL": {
            "Capital Social": [("Capital social subscrito e integralizado", {ano: 30000})],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }
    # Seções sem conta no ano viram lista vazia — nunca conta com valor zero.
    for secao in ("PNC",):
        for sub in list(plano[secao]):
            plano[secao][sub] = [x for x in plano[secao][sub] if x]
            if not plano[secao][sub]:
                del plano[secao][sub]
    return plano


# Contas cujo saldo é ESPELHO de outra entidade: aqui as duas pernas do mesmo
# saldo têm de casar no centavo, senão a eliminação do combinado não fecha e o
# book passa a acusar uma divergência que ninguém escreveu. Por isso elas ficam
# fora do ruído — e, de quebra, saldo intragrupo redondo é o que se vê na vida
# real, porque ele nasce de contrato, não de operação.
SEM_RUIDO = (
    "Mútuos a pagar", "Mútuos a receber",
    "Fornecedores intragrupo", "Contas a receber intragrupo",
    "Conta corrente a receber", "Conta corrente a pagar",
    "Aluguéis a pagar - Canastra", "Aluguéis a receber - Canastra",
)


PLANOS = {
    "industria": plano_industria,
    "comercial": plano_comercial,
    "transportes": plano_transportes,
    "agro": plano_agro,
    "imob": plano_imob,
}

# Ordem em que as empresas aparecem no combinado e nos quadros.
ORDEM = ["holding", "industria", "comercial", "transportes", "agro", "imob"]
CONTROLADAS = ["industria", "comercial", "transportes", "agro", "imob"]
