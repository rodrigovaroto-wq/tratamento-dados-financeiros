# -*- coding: utf-8 -*-
"""Plano de contas do book ARAUCÁRIA — 14 empresas, 5 exercícios (2021 a 2025).

TERCEIRO BOOK DO REPOSITÓRIO, e o primeiro cujo objetivo declarado é ser
CONFUSO. O `book-vertentes` representa o caso em que a extração é fiel e nada
deve abrir pendência; o `book-canastra` representa a dificuldade de um kit real
bem organizado. Este representa o kit que chega de um grupo que passou por uma
reestruturação societária no meio do período analisado — e que, por isso,
CONTRADIZ A SI MESMO em vários pontos sem que nenhum documento esteja errado.

A distinção que sustenta o book inteiro, e sem a qual ele seria só ruído:

    BAGUNÇADO NÃO É INCOMPLETO, E NÃO É INCONSISTENTE.

Cada balanço fecha. O combinado fecha nos quatro exercícios. Cada anexo lê o
balanço em vez de digitar o próprio total. O que é bagunçado é a LEITURA: a
mesma conta tem três nomes, a mesma empresa aparece com duas razões sociais, uma
controlada é incorporada no meio do histórico e o saldo dela reaparece dentro de
outra, dois documentos do mesmo período discordam porque um é anterior à
reclassificação — e a resposta certa de cada um desses conflitos está no
GABARITO. Conflito sem resposta certa não é teste, é ruído; e ruído não mede
nada porque qualquer saída passa.

A estrutura é a mesma do `book-canastra` (uma conta-folha por linha, nenhum
total digitado, `motor.py` resolve subtotais e valida por `assert`), com três
capacidades novas que a história exige:

  • ANOS_ATIVOS — empresa que NÃO EXISTIA num exercício, ou que foi incorporada
    e deixou de existir. Diferente de "existia e valia zero", exatamente como
    uma conta ausente é diferente de uma conta zerada;
  • INTRAGRUPO declarativo — as eliminações do combinado deixam de ser uma
    função escrita à mão par a par (que não escala para 14 empresas) e passam a
    ser uma TABELA lida dos dois lados;
  • PARTICIPACAO com dois minoritários, e não um — a participação de não
    controladores deixa de ter uma origem só, que é o caso em que somar errado
    ainda dá o número certo por acidente.
"""

GRUPO = "GRUPO ARAUCÁRIA"

# CINCO exercícios. A ordem é a cronológica — vários documentos dependem dela.
#
# 2021 é o ano PRÉ-CRISE, e ele não é curado conta a conta como os outros
# quatro: ele é construído para trás a partir de 2022, por uma regra DECLARADA
# grupo de contas a grupo de contas (`RETRO`, logo abaixo). Isto está escrito
# aqui, no `README.md` e no `GUIA_DE_TESTE.md` porque a diferença importa para
# quem for julgar uma rodada: nos exercícios de 2022 a 2025 cada saldo é uma
# escolha; em 2021 o saldo é consequência de uma regra, e a única coisa que ele
# prova é que a SÉRIE tem cinco pontos e uma direção coerente.
#
# O que ele acrescenta, e é o motivo de existir: cinco pontos realizados fazem o
# modelo ter história de verdade (média móvel, tendência, sazonalidade sobre 60
# meses) e fazem o PICO ficar DENTRO da janela — com quatro anos o kit já
# começava na descida.
ANOS = (2021, 2022, 2023, 2024, 2025)
ANO_RETRO = 2021
ANO_BASE_RETRO = 2022


# ---------------------------------------------------------------------------
# AS 14 EMPRESAS.
#
# `rotulo_caixa`: cada empresa nomeia o disponível do seu jeito, de propósito —
# são NOVE grafias diferentes para a mesma coisa, e duas delas diferem só por
# maiúscula e abreviação ("Caixa e bancos" × "Caixa e Bancos" × "Cx. e bancos").
# Um extrator que normalize demais funde as três e perde a empresa; um que não
# normalize nada trata como conceitos distintos. As duas saídas são erradas, e o
# gabarito diz qual é a certa.
#
# `razao_alternativa`: a razão social como ela aparece em ALGUNS documentos —
# nome de fantasia, grafia antiga, ou a razão anterior à alteração contratual.
# É a fonte da ambiguidade de entidade, que a `0146` tratou do lado do sistema.
#
# `anos`: em que exercícios a empresa EXISTE. Ausente = todos.
# ---------------------------------------------------------------------------
ENTIDADES = {
    "holding": {
        "razao_social": "ARAUCÁRIA PARTICIPAÇÕES E EMPREENDIMENTOS S.A.",
        "razao_alternativa": "Araucária Participações S.A.",
        "nome_fantasia": "Araucária Part.",
        "cnpj": "27.884.115/0001-08",
        "atividade": "Holding de instituições não financeiras",
        "rotulo_caixa": "Caixa e Equivalentes de Caixa",
    },
    "serraria": {
        "razao_social": "ARAUCÁRIA SERRARIA E BENEFICIAMENTO DE MADEIRAS LTDA.",
        "razao_alternativa": "Araucária Serraria Ltda.",
        "nome_fantasia": "Araucária Serraria",
        "cnpj": "27.884.116/0001-44",
        "atividade": "Serraria com desdobramento de madeira e beneficiamento",
        "rotulo_caixa": "Disponibilidades",
    },
    "paineis": {
        "razao_social": "ARAUCÁRIA PAINÉIS INDUSTRIALIZADOS S.A.",
        "razao_alternativa": "Araucária Painéis S/A",
        "nome_fantasia": "Araucária Painéis",
        "cnpj": "27.884.117/0001-99",
        "atividade": "Fabricação de painéis e chapas de madeira industrializada",
        "rotulo_caixa": "Caixa e bancos",
    },
    "moveis": {
        "razao_social": "ARAUCÁRIA MÓVEIS E DESIGN LTDA.",
        "razao_alternativa": "Araucária Móveis Ltda.",
        "nome_fantasia": "Araucária Móveis",
        "cnpj": "27.884.118/0001-33",
        "atividade": "Fabricação de móveis com predominância de madeira",
        "rotulo_caixa": "Caixa e Bancos",
    },
    "comercial": {
        "razao_social": "ARAUCÁRIA COMERCIAL E EXPORTAÇÃO LTDA.",
        "razao_alternativa": "Araucária Comercial Ltda.",
        "nome_fantasia": "Araucária Comercial",
        "cnpj": "27.884.119/0001-78",
        "atividade": "Comércio atacadista de madeira e derivados",
        "rotulo_caixa": "Numerário disponível",
    },
    "florestal": {
        "razao_social": "ARAUCÁRIA FLORESTAL E REFLORESTAMENTO LTDA.",
        "razao_alternativa": "Campos Gerais Reflorestamento Ltda.",
        "nome_fantasia": "Araucária Florestal",
        "cnpj": "27.884.120/0001-01",
        "atividade": "Produção florestal — florestas plantadas",
        "rotulo_caixa": "Cx. e bancos",
    },
    "transportes": {
        "razao_social": "AR TRANSPORTES RODOVIÁRIOS LTDA.",
        "razao_alternativa": "A.R. Transportes Ltda.",
        "nome_fantasia": "AR Log",
        "cnpj": "27.884.121/0001-46",
        "atividade": "Transporte rodoviário de cargas",
        "rotulo_caixa": "Bancos conta movimento",
    },
    "varejo": {
        "razao_social": "ARAUCÁRIA VAREJO E FRANQUIAS LTDA.",
        "razao_alternativa": "Araucária Franquias Ltda.",
        "nome_fantasia": "Araucária Varejo",
        "cnpj": "27.884.122/0001-90",
        "atividade": "Comércio varejista de móveis e gestão de franquias",
        "rotulo_caixa": "Caixa, bancos e aplicações de liquidez imediata",
    },
    "imob": {
        "razao_social": "ARAUCÁRIA IMOBILIÁRIA SPE LTDA.",
        "razao_alternativa": "Araucária SPE Imobiliária",
        "nome_fantasia": "Araucária SPE",
        "cnpj": "27.884.123/0001-35",
        "atividade": "Locação de imóveis próprios",
        "rotulo_caixa": "Caixa",
    },
    "agro": {
        "razao_social": "CAMPOS GERAIS AGROPECUÁRIA LTDA.",
        "razao_alternativa": "Campos Gerais Agro Ltda.",
        "nome_fantasia": "Campos Gerais",
        "cnpj": "27.884.124/0001-80",
        "atividade": "Criação de bovinos e cultivo de grãos",
        "rotulo_caixa": "Caixa e bancos",
    },
    "servicos": {
        "razao_social": "AR SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA.",
        "razao_alternativa": "AR Serviços Ltda.",
        "nome_fantasia": "AR Serviços",
        "cnpj": "27.884.125/0001-24",
        "atividade": "Atividades de serviços administrativos combinados",
        "rotulo_caixa": "Bancos",
    },
    # --- as três que não existem nos quatro exercícios ----------------------
    "metais": {
        "razao_social": "ARAUCÁRIA FERRAGENS E METAIS LTDA.",
        "razao_alternativa": "Araucária Ferragens Ltda.",
        "nome_fantasia": "Araucária Ferragens",
        "cnpj": "27.884.126/0001-69",
        "atividade": "Fabricação de artigos de metal para móveis",
        "rotulo_caixa": "Disponível",
        # INCORPORADA pela Serraria em 30/06/2024. Existe em 2022 e 2023; em
        # 2024 o saldo dela já está dentro da Serraria. Um kit que traga o
        # balanço de 2023 dela junto com o combinado de 2025 está CERTO — e a
        # leitura ingênua "somar todas as empresas de todos os anos" conta o
        # mesmo estoque duas vezes.
        "anos": (2021, 2022, 2023),
        "evento": "Incorporada pela Araucária Serraria em 30/06/2024 "
                  "(protocolo de incorporação de 12/05/2024).",
    },
    "energia": {
        "razao_social": "ARAUCÁRIA BIOENERGIA SPE LTDA.",
        "razao_alternativa": "Araucária Bioenergia SPE Ltda",
        "nome_fantasia": "Araucária Bioenergia",
        "cnpj": "27.884.127/0001-13",
        "atividade": "Geração de energia elétrica a partir de biomassa",
        "rotulo_caixa": "Caixa e equivalentes",
        # SPE constituída em 03/2023 para a termelétrica de biomassa que queima
        # o resíduo da serraria.
        "anos": (2023, 2024, 2025),
        "evento": "Constituída em 14/03/2023 (SPE do projeto de cogeração a biomassa).",
    },
    "trading": {
        "razao_social": "ARAUCÁRIA TRADING INTERNACIONAL LTDA.",
        "razao_alternativa": "Araucária Trading Ltda.",
        "nome_fantasia": "Araucária Trading",
        "cnpj": "27.884.128/0001-58",
        "atividade": "Comércio exterior — exportação de madeira e derivados",
        "rotulo_caixa": "Caixa e bancos - moeda nacional",
        "anos": (2024, 2025),
        "evento": "Constituída em 08/02/2024 para centralizar a exportação, "
                  "antes feita pela Araucária Comercial.",
    },
}


# Participação da holding em cada controlada.
#
# DOIS minoritários, e não um: AR Transportes (30%) e Araucária Varejo (45%). No
# `book-canastra` havia uma única origem de participação de não controladores, e
# uma origem só é o caso em que um erro de sinal ou de base ainda pode dar o
# número certo por acidente. Com duas origens de tamanhos diferentes, o total só
# fecha se as duas forem calculadas certo.
PARTICIPACAO = {
    "serraria": 1.00, "paineis": 1.00, "moveis": 1.00, "comercial": 1.00,
    "florestal": 1.00, "transportes": 0.70, "varejo": 0.55, "imob": 1.00,
    "agro": 1.00, "servicos": 1.00, "metais": 1.00, "energia": 1.00,
    "trading": 1.00,
}


# ---------------------------------------------------------------------------
# AS CONTRAPARTES INTRAGRUPO, EM TABELA.
#
# Cada linha diz: (rótulo da eliminação, empresa credora, seção, subseção,
# prefixo do rótulo). O motor LÊ o valor do lado credor no balanço já
# construído — nenhum número é digitado aqui, que é o que faz a eliminação
# fechar contra o outro lado em vez de contra uma constante.
#
# Por que virou tabela: com 6 empresas dava para escrever a função à mão (é o
# que o `book-canastra` faz). Com 14 empresas e 11 pares, a função à mão é o
# lugar onde um par esquecido não acusa nada — o combinado fecha do mesmo jeito,
# só com o ativo e o passivo inflados na mesma medida. Silêncio, de novo.
# ---------------------------------------------------------------------------
INTRAGRUPO = [
    ("Conta corrente AR Transportes × Araucária Serraria",
     "transportes", "AC", "Contas a Receber", "Conta corrente a receber"),
    ("Aluguéis Araucária SPE × Araucária Serraria",
     "imob", "AC", "Contas a Receber", "Aluguéis a receber"),
    ("Fornecimento Araucária Florestal × Araucária Serraria",
     "florestal", "AC", "Contas a Receber", "Contas a receber intragrupo"),
    ("Fornecimento Araucária Serraria × Araucária Painéis",
     "serraria", "AC", "Contas a Receber", "Contas a receber intragrupo"),
    ("Fornecimento Araucária Painéis × Araucária Móveis",
     "paineis", "AC", "Contas a Receber", "Contas a receber intragrupo"),
    ("Rateio AR Serviços × demais empresas",
     "servicos", "AC", "Contas a Receber", "Rateio de despesas a receber"),
    ("Vendas Araucária Móveis × Araucária Varejo",
     "moveis", "AC", "Contas a Receber", "Contas a receber intragrupo"),
    ("Comissões Araucária Trading × Araucária Comercial",
     "trading", "AC", "Contas a Receber", "Comissões a receber intragrupo"),
    ("Energia Araucária Bioenergia × Araucária Serraria",
     "energia", "AC", "Contas a Receber", "Energia a faturar intragrupo"),
    ("Suprimentos Araucária Ferragens × Araucária Móveis",
     "metais", "AC", "Contas a Receber", "Contas a receber intragrupo"),
    ("Arrendamento Campos Gerais × Araucária Florestal",
     "agro", "AC", "Contas a Receber", "Arrendamento a receber intragrupo"),
]


# ---------------------------------------------------------------------------
# Uma conta-folha por linha. `c()` recebe o rótulo e os valores por exercício.
#
# Ano AUSENTE significa que a conta NÃO EXISTIA naquele exercício — não que
# valia zero. A distinção é o ponto: no comparativo, a coluna do ano em que a
# conta não existe fica VAZIA, e um extrator que preencher zero ali está
# afirmando algo sobre o negócio que o documento não diz.
#
# O rótulo pode ser um dict {ano: texto} quando a grafia MUDA entre exercícios.
# Neste book isso não é exceção, é regra: o grupo trocou de escritório contábil
# na virada de 2023 para 2024, e o plano de contas foi reescrito junto.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# A REGRA DO EXERCÍCIO RETROATIVO (2021).
#
# Fator aplicado sobre o saldo de 2022, por SUBSEÇÃO. A direção de cada um conta
# a mesma história que os quatro exercícios curados, só que um passo antes:
#
#   • a dívida era MUITO menor (0,58) — o endividamento é o eixo da queda;
#   • as provisões e a inadimplência eram menores (0,40 e 0,55);
#   • o imobilizado era um pouco menor e a depreciação acumulada, bem menor;
#   • o capital social e as terras não se mexem (1,00);
#   • o giro operacional era MAIOR (1,08 em clientes e estoques): vendia-se mais.
#
# Conta que não existe em 2022 não recebe 2021 — a mesma regra de sempre: ausente
# é "não existia", e não "valia zero".
# ---------------------------------------------------------------------------
RETRO_PADRAO = 0.96
RETRO = {
    "Disponível": 1.42,
    "Contas a Receber": 1.08,
    "Estoques": 1.08,
    "Outros Créditos": 0.88,
    "Realizável a Longo Prazo": 0.72,
    "Investimentos": 1.00,
    "Ativos Biológicos": 0.94,
    "Propriedades para Investimento": 1.00,
    "Imobilizado": 0.94,
    "Intangível": 0.90,
    "Fornecedores": 0.86,
    "Empréstimos e Financiamentos": 0.58,
    "Obrigações Trabalhistas e Sociais": 1.06,
    "Obrigações Tributárias": 0.64,
    "Outras Obrigações": 0.92,
    "Provisões": 0.40,
    "Partes Relacionadas": 0.46,
    "Capital Social": 1.00,
    "Reservas de Lucros": 1.24,
}
# Exceções por rótulo, onde o fator da subseção contaria a história errada.
RETRO_POR_ROTULO = {
    "(-) Depreciação acumulada": 0.82,
    "(-) Amortização acumulada": 0.78,
    "(-) Provisão para créditos de liquidação duvidosa": 0.55,
    "(-) Perdas estimadas em créditos": 0.55,
    "Terrenos": 1.00,
    "Terras próprias": 1.00,
    "Terras agrícolas": 1.00,
    "Capital social": 1.00,
}


def _fator_retro(sub, rotulo_texto):
    for pref, f in RETRO_POR_ROTULO.items():
        if rotulo_texto.startswith(pref):
            return f
    return RETRO.get(sub, RETRO_PADRAO)


def com_retro(plano):
    """Acrescenta o exercício de `ANO_RETRO` a um plano, pela regra acima."""
    for secao, subs in plano.items():
        for sub, contas in subs.items():
            if contas == "PLUG":
                continue
            for rotulo, por_ano in contas:
                if ANO_BASE_RETRO not in por_ano or ANO_RETRO in por_ano:
                    continue
                texto = rotulo_do_ano(rotulo, ANO_BASE_RETRO)
                f = _fator_retro(sub, texto)
                por_ano[ANO_RETRO] = int(round(por_ano[ANO_BASE_RETRO] * f))
    return plano


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


def anos_da_entidade(k):
    return ENTIDADES[k].get("anos", ANOS)


def existe_em(k, ano):
    return ano in anos_da_entidade(k)


# ===========================================================================
# ARAUCÁRIA SERRARIA — a operacional principal, plano de contas detalhado.
#
# A história em quatro exercícios: 2022 é o ano bom (madeira em alta, exportação
# aquecida); 2023 o preço do pinus serrado cai 31% e a empresa segura estoque;
# 2024 ela incorpora a Ferragens (o estoque e o imobilizado dela entram aqui, e
# é por isso que duas contas DÃO UM SALTO que a operação não explica); 2025 ela
# opera com capital de terceiros, quebra o covenant de alavancagem, adere à
# transação tributária e antecipa recebíveis para fechar o mês.
#
# AS DUAS ARMADILHAS DESTE PLANO:
#  • "Estoques de madeira serrada" salta de 18.400 (2023) para 31.900 (2024) —
#    +73% num ano em que a receita CAIU. A explicação não está no balanço: está
#    na incorporação, e a nota explicativa é quem diz;
#  • "Outros créditos" existe em AC e em ANC com o MESMO rótulo. Não é erro de
#    digitação: é curto e longo prazo da mesma natureza, e é assim que aparece
#    no balancete. Um extrator que use o rótulo como chave funde os dois.
# ===========================================================================
def plano_serraria():
    return {
        "AC": {
            "Disponível": [
                c("Caixa", a2022=42, a2023=38, a2024=31, a2025=22),
                c("Bancos conta movimento", a2022=3180, a2023=1940, a2024=1120, a2025=406),
                c({2022: "Aplicações financeiras de liquidez imediata",
                   2024: "Aplicações financeiras"},
                  a2022=6400, a2023=2100, a2024=380),
            ],
            "Contas a Receber": [
                c({2022: "Clientes mercado interno",
                   2024: "Duplicatas a receber - mercado interno"},
                  a2022=28600, a2023=24100, a2024=21800, a2025=17400),
                c({2022: "Clientes mercado externo",
                   2024: "Duplicatas a receber - exportação"},
                  a2022=14200, a2023=9800, a2024=6100, a2025=3900),
                c("Contas a receber intragrupo", a2022=2400, a2023=2900,
                  a2024=3600, a2025=4300),
                # Nasce em 2024: é o sintoma do aperto de caixa.
                c("(-) Antecipação de recebíveis - cessão de crédito",
                  a2024=-4200, a2025=-7600),
                c({2022: "(-) Provisão para créditos de liquidação duvidosa",
                   2024: "(-) Perdas estimadas em créditos de liquidação duvidosa"},
                  a2022=-860, a2023=-1240, a2024=-2180, a2025=-3400),
            ],
            "Estoques": [
                c("Estoques de madeira serrada", a2022=21300, a2023=18400,
                  a2024=31900, a2025=27600),
                c("Madeira em toras - pátio", a2022=8900, a2023=7200,
                  a2024=9400, a2025=6800),
                c("Produtos em elaboração", a2022=3100, a2023=2800,
                  a2024=4900, a2025=4100),
                c("Materiais auxiliares e de manutenção", a2022=1900, a2023=1700,
                  a2024=3800, a2025=3200),
                c({2024: "Ferragens e componentes metálicos"}, a2024=5200, a2025=4400),
                c("(-) Provisão para obsolescência", a2023=-320, a2024=-1100, a2025=-2400),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar - ICMS", a2022=2100, a2023=2600,
                  a2024=3900, a2025=4800),
                c("Impostos a recuperar - PIS/COFINS", a2022=1400, a2023=1800,
                  a2024=2300, a2025=2900),
                c("Adiantamentos a fornecedores", a2022=1800, a2023=1200,
                  a2024=900, a2025=640),
                c("Despesas antecipadas", a2022=420, a2023=380, a2024=510, a2025=470),
                # MESMO rótulo que a conta do ANC. Deliberado.
                c("Outros créditos", a2022=680, a2023=740, a2024=1100, a2025=1360),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais", a2022=1900, a2023=2400, a2024=3100, a2025=4200),
                c({2024: "Créditos tributários - transação tributária"},
                  a2024=2800, a2025=2600),
                # MESMO rótulo que a conta do AC. Deliberado.
                c("Outros créditos", a2022=310, a2023=290, a2024=420, a2025=380),
            ],
            "Investimentos": [
                c("Participação em Araucária Bioenergia SPE (avaliada ao custo)",
                  a2023=4000, a2024=4000, a2025=4000),
            ],
            "Imobilizado": [
                c("Terrenos", a2022=12400, a2023=12400, a2024=12400, a2025=12400),
                c("Edificações e benfeitorias", a2022=28900, a2023=28900,
                  a2024=34600, a2025=34600),
                c({2022: "Máquinas, equipamentos e instalações",
                   2024: "Máquinas e equipamentos industriais"},
                  a2022=61200, a2023=63800, a2024=79400, a2025=80100),
                c("Veículos", a2022=4200, a2023=4200, a2024=5100, a2025=4600),
                c("Móveis, utensílios e equipamentos de informática",
                  a2022=2100, a2023=2300, a2024=2900, a2025=3000),
                c({2024: "Direito de uso - arrendamento de pátio (CPC 06 R2)"},
                  a2024=6800, a2025=5900),
                c("(-) Depreciação acumulada", a2022=-38400, a2023=-44100,
                  a2024=-53800, a2025=-62900),
            ],
            "Intangível": [
                c("Softwares e licenças", a2022=1400, a2023=1600, a2024=2100, a2025=2100),
                c({2024: "Ágio na incorporação Araucária Ferragens"}, a2024=3200, a2025=3200),
                c("(-) Amortização acumulada", a2022=-620, a2023=-840,
                  a2024=-1300, a2025=-1900),
            ],
        },
        "PC": {
            "Fornecedores": [
                c({2022: "Fornecedores nacionais",
                   2024: "Fornecedores - mercado interno"},
                  a2022=16800, a2023=18900, a2024=24600, a2025=29800),
                c("Fornecedores intragrupo", a2022=1900, a2023=2400,
                  a2024=3100, a2025=3900),
            ],
            "Empréstimos e Financiamentos": [
                c({2022: "Capital de giro - curto prazo",
                   2024: "Empréstimos e financiamentos - capital de giro"},
                  a2022=11200, a2023=18600, a2024=27400, a2025=36900),
                c("FINAME e finalidade específica", a2022=4800, a2023=4800,
                  a2024=6200, a2025=6200),
                c({2024: "Arrendamento a pagar (CPC 06 R2) - curto prazo"},
                  a2024=1400, a2025=1500),
                c({2025: "Nota de crédito à exportação (NCE)"}, a2025=8400),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários e ordenados a pagar", a2022=2900, a2023=3100,
                  a2024=4200, a2025=4600),
                c("Férias e 13º salário provisionados", a2022=3400, a2023=3600,
                  a2024=4900, a2025=5300),
                c("Encargos sociais a recolher", a2022=1600, a2023=1900,
                  a2024=2800, a2025=3600),
            ],
            "Obrigações Tributárias": [
                c("ICMS a recolher", a2022=1900, a2023=1600, a2024=2100, a2025=1400),
                c("PIS e COFINS a recolher", a2022=880, a2023=760, a2024=1100, a2025=690),
                c({2023: "Parcelamento tributário - curto prazo",
                   2025: "Transação tributária Lei 14.375 - curto prazo"},
                  a2023=1800, a2024=3400, a2025=4100),
            ],
            "Outras Obrigações": [
                c("Adiantamentos de clientes", a2022=2100, a2023=1800, a2024=2600, a2025=3400),
                c("Contas a pagar diversas", a2022=940, a2023=1200, a2024=1900, a2025=2600),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c({2022: "Capital de giro - longo prazo",
                   2024: "Empréstimos e financiamentos - longo prazo"},
                  a2022=24600, a2023=21800, a2024=18400, a2025=12900),
                c("FINAME - longo prazo", a2022=14200, a2023=11600,
                  a2024=14800, a2025=11200),
                c({2024: "Arrendamento a pagar (CPC 06 R2) - longo prazo"},
                  a2024=5600, a2025=4600),
            ],
            "Obrigações Tributárias": [
                c({2023: "Parcelamento tributário - longo prazo",
                   2025: "Transação tributária Lei 14.375 - longo prazo"},
                  a2023=6200, a2024=14800, a2025=18600),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2022=1800,
                  a2023=2600, a2024=4100, a2025=6300),
                c("Provisão para contingências tributárias", a2022=900,
                  a2023=1400, a2024=2200, a2025=3100),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=3800, a2023=6400,
                  a2024=9900, a2025=14600),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social subscrito e integralizado", a2022=40000,
                  a2023=40000, a2024=48000, a2025=48000),
            ],
            "Reservas de Lucros": [
                c("Reserva legal", a2022=2400, a2023=2400, a2024=2400),
                c("Reserva de lucros a realizar", a2022=6800, a2023=3100),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# ARAUCÁRIA PAINÉIS — a segunda operacional. Compra madeira da Serraria e vende
# painel para a Móveis: está no MEIO da cadeia intragrupo, e é por isso que ela
# aparece dos dois lados da eliminação.
# ===========================================================================
def plano_paineis():
    return {
        "AC": {
            "Disponível": [
                c("Caixa e bancos", a2022=2400, a2023=1800, a2024=980, a2025=410),
                c("Aplicações financeiras", a2022=3900, a2023=1600, a2024=290),
            ],
            "Contas a Receber": [
                c({2022: "Clientes", 2024: "Duplicatas a receber de clientes"},
                  a2022=19400, a2023=17200, a2024=15600, a2025=12800),
                c("Contas a receber intragrupo", a2022=3100, a2023=3600,
                  a2024=4200, a2025=5100),
                c({2022: "(-) Provisão para devedores duvidosos",
                   2024: "(-) Perdas estimadas em créditos"},
                  a2022=-540, a2023=-820, a2024=-1400, a2025=-2200),
            ],
            "Estoques": [
                c("Painéis acabados", a2022=12600, a2023=11800, a2024=10400, a2025=9100),
                c("Resinas, adesivos e insumos químicos", a2022=4200,
                  a2023=4800, a2024=5600, a2025=6400),
                c("Madeira e cavaco", a2022=3800, a2023=3400, a2024=3100, a2025=2600),
                c("(-) Provisão para obsolescência", a2024=-480, a2025=-1100),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar", a2022=2900, a2023=3400, a2024=4100, a2025=4900),
                c("Adiantamentos a fornecedores", a2022=1200, a2023=980, a2024=740, a2025=520),
                c("Despesas antecipadas", a2022=310, a2023=340, a2024=380, a2025=420),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais", a2022=1200, a2023=1600, a2024=2100, a2025=2800),
            ],
            "Imobilizado": [
                c("Terrenos", a2022=8600, a2023=8600, a2024=8600, a2025=8600),
                c("Edificações", a2022=19400, a2023=19400, a2024=19400, a2025=19400),
                c({2022: "Linha de prensagem e equipamentos",
                   2024: "Máquinas e equipamentos - linha de prensagem"},
                  a2022=48600, a2023=51200, a2024=51200, a2025=51900),
                c("Veículos e empilhadeiras", a2022=3100, a2023=3400, a2024=3400, a2025=3100),
                c("(-) Depreciação acumulada", a2022=-28900, a2023=-33600,
                  a2024=-38400, a2025=-43600),
            ],
            "Intangível": [
                c("Licenças ambientais e softwares", a2022=890, a2023=940, a2024=1100, a2025=1100),
                c("(-) Amortização acumulada", a2022=-310, a2023=-420, a2024=-560, a2025=-720),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores nacionais", a2022=11400, a2023=13200, a2024=16800, a2025=20400),
                c("Fornecedores intragrupo", a2022=2400, a2023=2900, a2024=3600, a2025=4300),
                c({2023: "Fornecedores no exterior - resinas"},
                  a2023=2600, a2024=4100, a2025=5800),
            ],
            "Empréstimos e Financiamentos": [
                c("Capital de giro", a2022=8600, a2023=13400, a2024=19800, a2025=26400),
                c("FINAME", a2022=3200, a2023=3200, a2024=3200, a2025=3200),
                c({2024: "ACC - adiantamento sobre contrato de câmbio"},
                  a2024=3900, a2025=6200),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2022=3900, a2023=4200, a2024=4600, a2025=5100),
            ],
            "Obrigações Tributárias": [
                c("Tributos a recolher", a2022=2100, a2023=1900, a2024=2400, a2025=1800),
                c({2024: "Parcelamento tributário - curto prazo"}, a2024=1900, a2025=2600),
            ],
            "Outras Obrigações": [
                c("Adiantamentos de clientes", a2022=1600, a2023=1400, a2024=2100, a2025=2900),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2022=18400, a2023=16200,
                  a2024=13800, a2025=9600),
                c("FINAME - longo prazo", a2022=9800, a2023=8100, a2024=6400, a2025=4600),
            ],
            "Obrigações Tributárias": [
                c({2024: "Parcelamento tributário - longo prazo"}, a2024=7400, a2025=9800),
            ],
            "Provisões": [
                c("Provisão para contingências", a2022=1400, a2023=2100, a2024=3200, a2025=4600),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=2600, a2023=4100,
                  a2024=6800, a2025=9400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=26000, a2023=26000, a2024=26000, a2025=26000),
            ],
            "Reservas de Lucros": [
                c("Reserva legal", a2022=1800, a2023=1800, a2024=1800),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# ARAUCÁRIA MÓVEIS — compra painel da Painéis e vende para a Varejo. A ponta da
# cadeia, e a que sofre primeiro quando o crédito ao consumidor fecha.
# ===========================================================================
def plano_moveis():
    return {
        "AC": {
            "Disponível": [
                c("Caixa e Bancos", a2022=1900, a2023=1200, a2024=640, a2025=290),
            ],
            "Contas a Receber": [
                c("Clientes - lojistas e magazines", a2022=16400, a2023=14800,
                  a2024=11900, a2025=8600),
                c("Contas a receber intragrupo", a2022=2100, a2023=2600,
                  a2024=3400, a2025=4100),
                c({2023: "Cartões de crédito a receber"}, a2023=1800, a2024=2400, a2025=2900),
                c("(-) Perdas estimadas em créditos", a2022=-680, a2023=-1100,
                  a2024=-1900, a2025=-2800),
            ],
            "Estoques": [
                c("Produtos acabados - linha residencial", a2022=8900,
                  a2023=9400, a2024=8100, a2025=6900),
                c("Produtos acabados - linha corporativa", a2022=4200,
                  a2023=3800, a2024=3100, a2025=2400),
                c("Matéria-prima - painéis e ferragens", a2022=5600,
                  a2023=5100, a2024=4600, a2025=3900),
                c("(-) Provisão para obsolescência de coleção", a2023=-420,
                  a2024=-980, a2025=-1800),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar", a2022=1400, a2023=1700, a2024=2100, a2025=2600),
                c("Adiantamentos diversos", a2022=620, a2023=540, a2024=480, a2025=390),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais", a2022=680, a2023=940, a2024=1300, a2025=1800),
            ],
            "Imobilizado": [
                c("Edificações e instalações", a2022=9400, a2023=9400, a2024=9400, a2025=9400),
                c("Máquinas e equipamentos", a2022=18600, a2023=19400,
                  a2024=19400, a2025=19800),
                c("Móveis, utensílios e showroom", a2022=2900, a2023=3200,
                  a2024=3200, a2025=3000),
                c("(-) Depreciação acumulada", a2022=-12400, a2023=-14900,
                  a2024=-17600, a2025=-20400),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores", a2022=8900, a2023=10400, a2024=12800, a2025=15400),
                c("Fornecedores intragrupo", a2022=3100, a2023=3600, a2024=4200, a2025=5100),
            ],
            "Empréstimos e Financiamentos": [
                c("Capital de giro", a2022=6400, a2023=9800, a2024=14200, a2025=18900),
                c({2024: "Desconto de duplicatas"}, a2024=2600, a2025=4100),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos a pagar", a2022=2600, a2023=2800,
                  a2024=2900, a2025=3100),
            ],
            "Obrigações Tributárias": [
                c("Tributos a recolher", a2022=1400, a2023=1200, a2024=1600, a2025=1100),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2022=11200, a2023=9600,
                  a2024=7800, a2025=5400),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2022=780,
                  a2023=1200, a2024=1900, a2025=2800),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=1900, a2023=3200,
                  a2024=5100, a2025=7400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=14000, a2023=14000, a2024=14000, a2025=14000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# ARAUCÁRIA COMERCIAL — exportação até 2023; em 2024 a operação de exportação
# migra para a Trading, e é por isso que a receita dela CAI 62% sem que nada
# tenha piorado. É a armadilha de série temporal do book: a queda é REAL no
# documento e FALSA como sinal de deterioração.
# ===========================================================================
def plano_comercial():
    return {
        "AC": {
            "Disponível": [
                c("Numerário disponível", a2022=4100, a2023=2900, a2024=1600, a2025=890),
            ],
            "Contas a Receber": [
                c({2022: "Clientes no exterior",
                   2024: "Clientes no exterior (operação residual)"},
                  a2022=22400, a2023=18600, a2024=6100, a2025=3900),
                c("Clientes mercado interno", a2022=6800, a2023=7400,
                  a2024=8900, a2025=9600),
                c("(-) Perdas estimadas em créditos", a2022=-420, a2023=-680,
                  a2024=-940, a2025=-1400),
            ],
            "Estoques": [
                c("Mercadorias para revenda", a2022=9600, a2023=8400, a2024=4200, a2025=3100),
                c({2022: "Mercadorias em trânsito - exportação"}, a2022=3400, a2023=2800),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar - exportação", a2022=4800, a2023=5400,
                  a2024=3900, a2025=3100),
                c({2022: "Variação cambial ativa a apropriar"}, a2022=890, a2023=1200),
            ],
        },
        "ANC": {
            "Realizável a Longo Prazo": [
                c("Depósitos judiciais", a2022=420, a2023=560, a2024=740, a2025=980),
            ],
            "Imobilizado": [
                c("Instalações e benfeitorias em imóveis de terceiros",
                  a2022=2400, a2023=2400, a2024=2400, a2025=2400),
                c("Móveis, utensílios e informática", a2022=1100, a2023=1300,
                  a2024=1300, a2025=1200),
                c("(-) Depreciação acumulada", a2022=-1600, a2023=-2100,
                  a2024=-2500, a2025=-2900),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores nacionais", a2022=7900, a2023=8600, a2024=5100, a2025=4200),
                c("Fornecedores intragrupo", a2022=1400, a2023=1800, a2024=2100, a2025=2400),
            ],
            "Empréstimos e Financiamentos": [
                c({2022: "ACC - adiantamento sobre contrato de câmbio"},
                  a2022=12600, a2023=9400, a2024=2100),
                c("Capital de giro", a2022=3400, a2023=5800, a2024=8900, a2025=12400),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2022=1900, a2023=2100,
                  a2024=1400, a2025=1200),
            ],
            "Obrigações Tributárias": [
                c("Tributos a recolher", a2022=1200, a2023=1400, a2024=980, a2025=740),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2022=6800, a2023=5900,
                  a2024=4800, a2025=3400),
            ],
            "Provisões": [
                c("Provisão para contingências", a2022=640, a2023=890, a2024=1200, a2025=1700),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=1600, a2023=2400,
                  a2024=3800, a2025=5600),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=9000, a2023=9000, a2024=9000, a2025=9000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# ARAUCÁRIA FLORESTAL — floresta plantada (ativo biológico ao valor justo).
# Fornece tora para a Serraria e arrenda terra da Campos Gerais: aparece nos
# dois lados de eliminações diferentes.
# ===========================================================================
def plano_florestal():
    return {
        "AC": {
            "Disponível": [
                c("Cx. e bancos", a2022=1400, a2023=980, a2024=620, a2025=310),
            ],
            "Contas a Receber": [
                c("Contas a receber intragrupo", a2022=3900, a2023=4600,
                  a2024=5400, a2025=6200),
                c("Clientes terceiros - madeira em pé", a2022=2800, a2023=2400,
                  a2024=1900, a2025=1400),
            ],
            "Estoques": [
                c({2022: "Madeira colhida em pátio"}, a2022=2100, a2023=1800,
                  a2024=1400, a2025=1100),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar", a2022=620, a2023=740, a2024=890, a2025=1100),
            ],
        },
        "ANC": {
            "Ativos Biológicos": [
                c({2022: "Floresta plantada - pinus (valor justo)",
                   2024: "Ativos biológicos - pinus taeda (valor justo)"},
                  a2022=48600, a2023=52400, a2024=49800, a2025=44200),
                c({2022: "Floresta plantada - eucalipto (valor justo)",
                   2024: "Ativos biológicos - eucalipto (valor justo)"},
                  a2022=18400, a2023=21600, a2024=23800, a2025=25100),
            ],
            "Imobilizado": [
                c("Terras próprias", a2022=31200, a2023=31200, a2024=31200, a2025=31200),
                c("Máquinas florestais e implementos", a2022=8600, a2023=9400,
                  a2024=9400, a2025=8900),
                c("(-) Depreciação acumulada", a2022=-4100, a2023=-5600,
                  a2024=-7200, a2025=-8900),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores - silvicultura e colheita", a2022=3400,
                  a2023=3900, a2024=4600, a2025=5400),
                c("Arrendamento a pagar intragrupo", a2022=1200, a2023=1400,
                  a2024=1700, a2025=2100),
            ],
            "Empréstimos e Financiamentos": [
                c({2022: "Crédito rural - custeio", 2024: "Financiamento rural - custeio"},
                  a2022=6800, a2023=8400, a2024=10600, a2025=13400),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2022=1600, a2023=1800,
                  a2024=1900, a2025=2100),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c({2022: "Crédito rural - investimento",
                   2024: "Financiamento rural - investimento"},
                  a2022=22400, a2023=21600, a2024=20100, a2025=17800),
            ],
            "Provisões": [
                c("Provisão para contingências ambientais", a2022=890,
                  a2023=1200, a2024=1800, a2025=2600),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=2900, a2023=4600,
                  a2024=6800, a2025=9200),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=38000, a2023=38000, a2024=38000, a2025=38000),
            ],
            "Reservas de Lucros": [
                c({2022: "Ajuste de avaliação patrimonial - ativos biológicos"},
                  a2022=12400, a2023=16800, a2024=14200, a2025=9600),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# AS DEMAIS — planos mais curtos, porque a função delas no book é outra: elas
# existem para dar VOLUME e AMBIGUIDADE ao combinado (14 colunas, dois
# minoritários, três empresas com vida parcial), não para ter profundidade de
# plano de contas. Profundidade está na Serraria, na Painéis e na Móveis.
# ===========================================================================
def plano_transportes():
    return {
        "AC": {
            "Disponível": [
                c("Bancos conta movimento", a2022=890, a2023=640, a2024=380, a2025=140),
            ],
            "Contas a Receber": [
                c("Fretes a faturar e a receber", a2022=5400, a2023=4900,
                  a2024=4100, a2025=3400),
                c("Conta corrente a receber - Araucária Serraria",
                  a2022=1400, a2023=1800, a2024=2400, a2025=3100),
            ],
            "Outros Créditos": [
                c("Adiantamentos a motoristas e agregados", a2022=340,
                  a2023=390, a2024=460, a2025=540),
                c("Créditos de ICMS sobre combustível", a2022=210, a2023=260,
                  a2024=320, a2025=410),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Veículos, cavalos mecânicos e carretas", a2022=18400,
                  a2023=18400, a2024=17200, a2025=15600),
                c("Equipamentos de rastreamento e telemetria", a2022=740,
                  a2023=820, a2024=890, a2025=890),
                c("(-) Depreciação acumulada", a2022=-8900, a2023=-11200,
                  a2024=-13100, a2025=-14800),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores - combustível, pneus e manutenção",
                  a2022=2600, a2023=3100, a2024=3800, a2025=4600),
            ],
            "Empréstimos e Financiamentos": [
                c("FINAME - frota", a2022=3200, a2023=3200, a2024=3200, a2025=3200),
                c("Capital de giro", a2022=1200, a2023=2400, a2024=3900, a2025=5600),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos a pagar", a2022=1400,
                  a2023=1600, a2024=1800, a2025=2000),
            ],
            "Obrigações Tributárias": [
                c("ISS e ICMS sobre serviços de transporte a recolher",
                  a2022=260, a2023=310, a2024=390, a2025=480),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("FINAME - longo prazo", a2022=7400, a2023=6100, a2024=4800, a2025=3400),
            ],
            "Provisões": [
                c("Provisão para contingências trabalhistas", a2022=540,
                  a2023=890, a2024=1400, a2025=2100),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=1100, a2023=1900,
                  a2024=2900, a2025=4200),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=4000, a2023=4000, a2024=4000, a2025=4000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_varejo():
    return {
        "AC": {
            "Disponível": [
                c("Caixa, bancos e aplicações de liquidez imediata",
                  a2022=2100, a2023=1600, a2024=940, a2025=520),
            ],
            "Contas a Receber": [
                c("Cartões e recebíveis de franqueados", a2022=6900,
                  a2023=7400, a2024=6100, a2025=4800),
                c("Royalties de franquia a receber", a2022=1200, a2023=1400,
                  a2024=1100, a2025=890),
                c("(-) Perdas estimadas em créditos", a2022=-310, a2023=-540,
                  a2024=-890, a2025=-1400),
            ],
            "Estoques": [
                c("Mercadorias em lojas próprias", a2022=5400, a2023=5900,
                  a2024=5100, a2025=4200),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar", a2022=740, a2023=890, a2024=1100, a2025=1400),
                c("Adiantamentos a fornecedores", a2022=420, a2023=380, a2024=310, a2025=240),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Benfeitorias em imóveis de terceiros - lojas",
                  a2022=8900, a2023=10400, a2024=10400, a2025=9600),
                c("Móveis, utensílios e equipamentos de loja",
                  a2022=3400, a2023=3900, a2024=3900, a2025=3600),
                c("(-) Depreciação acumulada", a2022=-4200, a2023=-5900,
                  a2024=-7600, a2025=-9100),
            ],
            "Intangível": [
                c({2022: "Ponto comercial e luvas", 2024: "Direito de uso de ponto comercial"},
                  a2022=2600, a2023=2600, a2024=2600, a2025=2600),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores", a2022=6400, a2023=7100, a2024=6800, a2025=6200),
                c("Fornecedores intragrupo", a2022=2100, a2023=2600, a2024=3400, a2025=4100),
            ],
            "Empréstimos e Financiamentos": [
                c("Capital de giro", a2022=3900, a2023=5600, a2024=7800, a2025=10400),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2022=2400, a2023=2600,
                  a2024=2400, a2025=2100),
            ],
            "Obrigações Tributárias": [
                c("Tributos a recolher", a2022=890, a2023=790, a2024=1100, a2025=1400),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2022=5400, a2023=4600,
                  a2024=3800, a2025=2600),
            ],
            "Provisões": [
                c("Provisão para contingências", a2022=420, a2023=740, a2024=1200, a2025=1900),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=890, a2023=1600,
                  a2024=2600, a2025=3900),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=6000, a2023=6000, a2024=6000, a2025=6000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_imob():
    return {
        "AC": {
            "Disponível": [
                c("Caixa", a2022=310, a2023=240, a2024=180, a2025=96),
            ],
            "Contas a Receber": [
                c("Aluguéis a receber - Araucária Serraria", a2022=1600,
                  a2023=1900, a2024=2300, a2025=2800),
                c("Aluguéis a receber - terceiros", a2022=890, a2023=940,
                  a2024=1100, a2025=1200),
            ],
        },
        "ANC": {
            "Propriedades para Investimento": [
                c({2022: "Imóveis destinados a locação (custo)",
                   2024: "Propriedades para investimento (valor justo)"},
                  a2022=42600, a2023=42600, a2024=46800, a2025=46800),
                c("(-) Depreciação acumulada", a2022=-6400, a2023=-7900, a2024=-9400),
            ],
        },
        "PC": {
            "Empréstimos e Financiamentos": [
                c("Financiamento imobiliário - curto prazo", a2022=2400,
                  a2023=2400, a2024=2400, a2025=2400),
            ],
            "Obrigações Tributárias": [
                c("IPTU e tributos a recolher", a2022=310, a2023=340, a2024=390, a2025=440),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Financiamento imobiliário - longo prazo", a2022=26800,
                  a2023=24400, a2024=22000, a2025=19600),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=1400, a2023=2100,
                  a2024=3100, a2025=4400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=12000, a2023=12000, a2024=12000, a2025=12000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_agro():
    return {
        "AC": {
            "Disponível": [
                c("Caixa e bancos", a2022=640, a2023=480, a2024=310, a2025=180),
            ],
            "Contas a Receber": [
                c("Arrendamento a receber intragrupo", a2022=1200, a2023=1400,
                  a2024=1700, a2025=2100),
                c("Clientes - grãos e pecuária", a2022=3400, a2023=3900,
                  a2024=3100, a2025=2400),
            ],
            "Estoques": [
                c("Grãos armazenados", a2022=2900, a2023=3400, a2024=2600, a2025=1900),
                c({2022: "Rebanho em formação"}, a2022=4600, a2023=4900,
                  a2024=4200, a2025=3400),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Terras agrícolas", a2022=28400, a2023=28400, a2024=28400, a2025=28400),
                c("Máquinas agrícolas", a2022=9600, a2023=10400, a2024=10400, a2025=9800),
                c("(-) Depreciação acumulada", a2022=-4900, a2023=-6400,
                  a2024=-7900, a2025=-9400),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores - insumos agrícolas", a2022=2600, a2023=3100,
                  a2024=3600, a2025=4200),
            ],
            "Empréstimos e Financiamentos": [
                c("Custeio agrícola", a2022=4900, a2023=6100, a2024=7800, a2025=9800),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Investimento agrícola - longo prazo", a2022=14200,
                  a2023=13100, a2024=11900, a2025=10400),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=780, a2023=1400,
                  a2024=2200, a2025=3200),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=18000, a2023=18000, a2024=18000, a2025=18000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_servicos():
    return {
        "AC": {
            "Disponível": [
                c("Bancos", a2022=420, a2023=380, a2024=290, a2025=160),
            ],
            "Contas a Receber": [
                c("Rateio de despesas a receber - empresas do grupo",
                  a2022=2400, a2023=2900, a2024=3600, a2025=4400),
            ],
            "Outros Créditos": [
                c("Adiantamentos a empregados", a2022=180, a2023=210, a2024=260, a2025=310),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Equipamentos de informática e infraestrutura de TI",
                  a2022=2900, a2023=3400, a2024=3900, a2025=3900),
                c("(-) Depreciação acumulada", a2022=-1400, a2023=-2100,
                  a2024=-2900, a2025=-3400),
            ],
            "Intangível": [
                c({2023: "Sistema ERP - implantação"}, a2023=4200, a2024=4200, a2025=4200),
                c({2024: "(-) Amortização acumulada do ERP"}, a2024=-840, a2025=-1680),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores de serviços e licenças", a2022=890, a2023=1200,
                  a2024=1600, a2025=2100),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos a pagar", a2022=3100, a2023=3600,
                  a2024=4100, a2025=4600),
            ],
            "Obrigações Tributárias": [
                c("Tributos a recolher", a2022=640, a2023=740, a2024=890, a2025=1100),
            ],
        },
        "PNC": {
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=1900, a2023=3100,
                  a2024=4600, a2025=6400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=1000, a2023=1000, a2024=1000, a2025=1000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# --- as três de vida parcial ------------------------------------------------
def plano_metais():
    """INCORPORADA em 30/06/2024. Só existe em 2022 e 2023."""
    return {
        "AC": {
            "Disponível": [
                c("Disponível", a2022=680, a2023=410),
            ],
            "Contas a Receber": [
                c("Contas a receber intragrupo", a2022=1900, a2023=2400),
                c("Clientes terceiros", a2022=3100, a2023=2600),
            ],
            "Estoques": [
                c("Ferragens e componentes metálicos", a2022=4800, a2023=5200),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar", a2022=390, a2023=460),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Máquinas e equipamentos", a2022=6400, a2023=6400),
                c("(-) Depreciação acumulada", a2022=-2900, a2023=-3600),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores", a2022=2400, a2023=2900),
            ],
            "Empréstimos e Financiamentos": [
                c("Capital de giro", a2022=1900, a2023=3100),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2022=890, a2023=940),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Capital de giro - longo prazo", a2022=3400, a2023=2900),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2022=620, a2023=1100),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2022=3000, a2023=3000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_energia():
    """SPE constituída em 14/03/2023. Não existe em 2022."""
    return {
        "AC": {
            "Disponível": [
                c("Caixa e equivalentes", a2023=1900, a2024=1100, a2025=640),
            ],
            "Contas a Receber": [
                c("Energia a faturar intragrupo", a2023=890, a2024=1600, a2025=2400),
                c("Energia a faturar - mercado livre", a2024=1200, a2025=2100),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar sobre a implantação", a2023=2400,
                  a2024=1800, a2025=1200),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c({2023: "Obras em andamento - termelétrica de biomassa",
                   2025: "Usina termelétrica de biomassa"},
                  a2023=28400, a2024=41600, a2025=44200),
                c("(-) Depreciação acumulada", a2025=-2200),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores de EPC e equipamentos", a2023=4600, a2024=3100, a2025=1900),
            ],
            "Empréstimos e Financiamentos": [
                c("Financiamento de projeto - curto prazo", a2024=2800, a2025=4200),
            ],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [
                c("Financiamento de projeto (BNDES) - longo prazo",
                  a2023=22400, a2024=31800, a2025=29600),
            ],
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2023=1400, a2024=2600, a2025=4100),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2023=4000, a2024=8000, a2025=8000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


def plano_trading():
    """Constituída em 08/02/2024 — recebe a operação de exportação da Comercial."""
    return {
        "AC": {
            "Disponível": [
                c("Caixa e bancos - moeda nacional", a2024=1400, a2025=890),
                c("Bancos - conta em moeda estrangeira", a2024=2900, a2025=1600),
            ],
            "Contas a Receber": [
                c("Clientes no exterior", a2024=14600, a2025=16800),
                c("Comissões a receber intragrupo", a2024=890, a2025=1400),
            ],
            "Estoques": [
                c("Mercadorias em trânsito - exportação", a2024=4200, a2025=5100),
            ],
            "Outros Créditos": [
                c("Impostos a recuperar - exportação", a2024=2100, a2025=3400),
            ],
        },
        "ANC": {
            "Imobilizado": [
                c("Móveis, utensílios e informática", a2024=890, a2025=940),
                c("(-) Depreciação acumulada", a2024=-180, a2025=-380),
            ],
        },
        "PC": {
            "Fornecedores": [
                c("Fornecedores intragrupo", a2024=3900, a2025=5400),
            ],
            "Empréstimos e Financiamentos": [
                c("ACC - adiantamento sobre contrato de câmbio", a2024=9800, a2025=13400),
            ],
            "Obrigações Trabalhistas e Sociais": [
                c("Salários, férias e encargos", a2024=640, a2025=890),
            ],
        },
        "PNC": {
            "Partes Relacionadas": [
                c("Mútuos a pagar - controladora", a2024=1200, a2025=2400),
            ],
        },
        "PL": {
            "Capital Social": [
                c("Capital social", a2024=2000, a2025=2000),
            ],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }


# ===========================================================================
# A HOLDING. Montada pelo motor DEPOIS das controladas: o ativo dela é o PL
# delas (MEP) e o mútuo a receber é o espelho do que elas declaram dever.
# ===========================================================================
def plano_holding(ano, mep_positivo, provisao, mutuos):
    ativo_fixo = {
        "Caixa e Equivalentes de Caixa": {2022: 2400, 2023: 1600, 2024: 890, 2025: 410},
        "Impostos a recuperar": {2022: 310, 2023: 380, 2024: 460, 2025: 540},
    }
    plano = {
        "AC": {
            "Disponível": [("Caixa e Equivalentes de Caixa",
                            ativo_fixo["Caixa e Equivalentes de Caixa"])],
            "Outros Créditos": [("Impostos a recuperar", ativo_fixo["Impostos a recuperar"])],
        },
        "ANC": {
            "Partes Relacionadas": [("Mútuos a receber - controladas", {ano: mutuos})],
            "Investimentos": [(rot, {ano: v}) for rot, v in mep_positivo],
        },
        "PC": {
            "Outras Obrigações": [("Contas a pagar diversas",
                                   {2022: 420, 2023: 560, 2024: 740, 2025: 980})],
        },
        "PNC": {
            "Empréstimos e Financiamentos": [("Empréstimo com garantia de recebíveis do grupo",
                             {2022: 8400, 2023: 12600, 2024: 18900, 2025: 26400})],
        },
        "PL": {
            "Capital Social": [("Capital social",
                                {2022: 90000, 2023: 90000, 2024: 106000, 2025: 106000})],
            "Lucros ou Prejuízos Acumulados": "PLUG",
        },
    }
    if provisao:
        plano["PNC"]["Provisões"] = [
            ("Provisão para passivo a descoberto em controladas", {ano: provisao})]
    return plano


# ---------------------------------------------------------------------------
# Contas cujo valor NÃO pode receber ruído: elas são espelho de um número que já
# existe em outra entidade, e o ruído aqui quebraria a eliminação do combinado.
# ---------------------------------------------------------------------------
SEM_RUIDO = (
    "Mútuos a pagar", "Mútuos a receber",
    "Fornecedores intragrupo", "Contas a receber intragrupo",
    "Conta corrente a receber", "Conta corrente a pagar",
    "Aluguéis a pagar", "Aluguéis a receber",
    "Rateio de despesas a receber", "Rateio de despesas a pagar",
    "Comissões a receber intragrupo", "Comissões a pagar intragrupo",
    "Energia a faturar intragrupo", "Energia a pagar intragrupo",
    "Arrendamento a receber intragrupo", "Arrendamento a pagar intragrupo",
)


def _com_retro(fn):
    return lambda: com_retro(fn())


PLANOS = {
    "serraria": _com_retro(plano_serraria),
    "paineis": _com_retro(plano_paineis),
    "moveis": _com_retro(plano_moveis),
    "comercial": _com_retro(plano_comercial),
    "florestal": _com_retro(plano_florestal),
    "transportes": _com_retro(plano_transportes),
    "varejo": _com_retro(plano_varejo),
    "imob": _com_retro(plano_imob),
    "agro": _com_retro(plano_agro),
    "servicos": _com_retro(plano_servicos),
    "metais": _com_retro(plano_metais),
    "energia": _com_retro(plano_energia),
    "trading": _com_retro(plano_trading),
}

# Ordem em que as empresas aparecem no combinado e nos quadros.
ORDEM = ["holding", "serraria", "paineis", "moveis", "comercial", "florestal",
         "transportes", "varejo", "imob", "agro", "servicos", "metais",
         "energia", "trading"]
CONTROLADAS = [k for k in ORDEM if k != "holding"]

# As cinco com plano de contas profundo — as que recebem o jogo completo de
# anexos (DFC, DMPL, DVA, balancete, razão, aging, estoque…).
PRINCIPAIS = ["serraria", "paineis", "moveis", "comercial", "florestal"]
