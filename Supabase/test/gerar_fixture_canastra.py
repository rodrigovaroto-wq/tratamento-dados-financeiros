# -*- coding: utf-8 -*-
"""Gera `fixture_book_canastra.sql` a partir do gerador do book CANASTRA.

POR QUE ELE EXISTE, e por que não bastava o `gerar_fixture.py`.

O `fixture_book_vertentes.sql` representa o caso em que **a extração é fiel e o
documento é fácil**: dois exercícios, uma conta por grupo, nenhum total impresso,
uma escala só. Ele prova que a reconciliação não grita à toa — e é o único
cenário que ela via. O `book-canastra` existe desde o PR #112 para ser o oposto
disso (3 exercícios, 6 empresas, 16 tipos documentais, 15 armadilhas), mas até
aqui ele só provava o GERADOR (que os números fecham no papel) e o ORÇAMENTO
(que o lote não cabe no teto de gasto). **A ingestão nunca foi exercitada sobre
ele.** Era a maior lacuna de cobertura viva do repositório.

O QUE ESTE FIXTURE REPRESENTA. A mesma coisa que o de Vertentes — uma extração
FIEL — só que sobre documentos DIFÍCEIS. A dificuldade está no papel, não no
extrator: rótulo que muda de nome entre exercícios, conta que nasce no meio do
histórico, quatro escalas no mesmo caso, tranche em dólar, coluna "Eliminações"
que não é empresa, não controladores, prognóstico de contingência, documento sem
um número monetário sequer.

A REGRA QUE ELE TRAVA, portanto, é a mesma e é mais forte: **documento difícil,
extração fiel => a única pendência é a divergência que o book planta de
propósito** (R$ 240 mil de mútuos). Toda armadilha que virar pendência aqui é
falso positivo, e falso positivo ensina o analista a ignorar o aviso.

Uso (de dentro de Dados de Teste/book-canastra, que é onde os módulos do book vivem):

    cd "Dados de Teste"/book-canastra
    python3 ../../Supabase/test/gerar_fixture_canastra.py > ../../Supabase/test/fixture_book_canastra.sql

O `.sql` gerado é versionado para que `Supabase/test/run.sh` rode sem Python — igual ao
de Vertentes. Com `--json` emite os mesmos dados no formato que o verificador do
export consome.
"""
import json
import sys

import dados as D
import demonstracoes as X
import motor as M

bp, tot = M.construir()

CASO = "'11111111-3333-3333-3333-111111111111'"

# Os uuids são estáveis e legíveis de propósito: quando um assert falha, o valor
# que aparece na mensagem tem de dizer QUEM é sem uma consulta a mais.
ENT = {
    "holding":     "22222222-3333-0000-0000-000000000001",
    "industria":   "22222222-3333-0000-0000-000000000002",
    "comercial":   "22222222-3333-0000-0000-000000000003",
    "transportes": "22222222-3333-0000-0000-000000000004",
    "agro":        "22222222-3333-0000-0000-000000000005",
    "imob":        "22222222-3333-0000-0000-000000000006",
    "grupo":       "22222222-3333-0000-0000-000000000007",
}
NOME = {k: D.ENTIDADES[k]["razao_social"] for k in D.ENTIDADES}
NOME["grupo"] = D.GRUPO

# Fatia 1.3 — mesma correção e mesmo motivo do `gerar_fixture.py` (book
# Vertentes): o valor literal 'alvo' não bate nenhum dos 5 rótulos do enum
# `entidade_papel_no_grupo` (migration 0179) e quebraria o `alter column`. A
# chave já escolhida em `ENT` por quem escreveu este gerador ("holding",
# "imob" = SPE) é o sinal usado — nada novo é inferido.
PAPEL = {
    "holding": "holding",
    "industria": "operacional",
    "comercial": "operacional",
    "transportes": "operacional",
    "agro": "operacional",
    "imob": "veiculo",
    "grupo": "holding",
}

# TRÊS exercícios, e é isso que separa este book do primeiro: o comparativo tem
# três colunas, e a série realizada do modelo tem três pontos em vez de dois.
PER = {
    "multi_232425": ("33333333-3333-0000-0000-000000000001", "multi", "23,24,25"),
    "multi_2425":   ("33333333-3333-0000-0000-000000000002", "multi", "24,25"),
    "anual_2025":   ("33333333-3333-0000-0000-000000000003", "anual", "2025"),
    "base_251231":  ("33333333-3333-0000-0000-000000000004", "data-base", "2025-12-31"),
    "l36m":         ("33333333-3333-0000-0000-000000000005", "L36M", "23,24,25"),
}

SEC_ATIVO = "ATIVO"
SEC_PASSIVO = "PASSIVO E PATRIMÔNIO LÍQUIDO"

NC = "NAO_CLASSIFICAVEL"
CANON_BP = {"AC": "ativo_circulante", "ANC": "ativo_nao_circulante",
            "PC": "passivo_circulante", "PNC": "passivo_nao_circulante",
            "PL": "patrimonio_liquido"}
CANON_BP_LABEL = {"Ativo Circulante": "ativo_circulante",
                  "Ativo Não Circulante": "ativo_nao_circulante",
                  "Passivo Circulante": "passivo_circulante",
                  "Passivo Não Circulante": "passivo_nao_circulante",
                  "Patrimônio Líquido": "patrimonio_liquido"}
# A cascata da DRE do Canastra imprime o subtotal COM VALOR (é o "total impresso"
# que a v46 mostrou faltar na extração). O rótulo do subtotal/âncora que abre o
# bloco é o que define a seção canônica das contas abaixo dele.
CANON_DRE = {
    "RECEITA OPERACIONAL BRUTA": "receita_bruta",
    "(-) DEDUÇÕES DA RECEITA BRUTA": "receita_bruta",
    "RECEITA OPERACIONAL LÍQUIDA": "receita_bruta",
    "(-) CUSTO DOS PRODUTOS VENDIDOS E DOS SERVIÇOS PRESTADOS": "custos",
    "LUCRO BRUTO": "custos",
    "(-) DESPESAS OPERACIONAIS": "despesas_operacionais",
    "RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO": "despesas_operacionais",
    "RESULTADO FINANCEIRO LÍQUIDO": "resultado_financeiro",
    "RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO": "impostos_lucro",
    "PREJUÍZO DO EXERCÍCIO": NC,
}
CANON_DFC = {
    "FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS": "atividades_operacionais",
    "FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO": "atividades_investimento",
    "FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO": "atividades_financiamento",
}


# O balancete não tem seção impressa: quem diz onde a conta mora é o CÓDIGO
# contábil, e quem dá o SINAL é a coluna D/C — o valor sai sempre em módulo,
# como num balancete de verdade. Ler a coluna de valor sozinha inverte o passivo
# inteiro; ler o parêntese do rótulo não funciona porque aqui não há parêntese.
_POR_CODIGO = {
    "1.1": ("Ativo Circulante", "ativo_circulante", "D"),
    "1.2": ("Ativo Não Circulante", "ativo_nao_circulante", "D"),
    "2.1": ("Passivo Circulante", "passivo_circulante", "C"),
    "2.2": ("Passivo Não Circulante", "passivo_nao_circulante", "C"),
    "2.3": ("Patrimônio Líquido", "patrimonio_liquido", "C"),
}


def _do_codigo(codigo):
    return _POR_CODIGO[".".join(codigo.split(".")[:2])]


def _valor_do_balancete(codigo, valor, natureza):
    """Positivo quando a natureza é a ESPERADA para o grupo do código; negativo
    quando ela está invertida, que é como um balancete registra conta redutora."""
    return valor if natureza == _do_codigo(codigo)[2] else -valor


def q(s):
    return "null" if s is None else "'" + str(s).replace("'", "''") + "'"


def n(v):
    return "null" if v is None else repr(float(v))


docs = []


def doc(idx, tipo, ent, per_key, arquivo=None):
    d = {
        "doc": f"44444444-3333-0000-0000-0000000000{idx:02d}",
        "ver": f"55555555-3333-0000-0000-0000000000{idx:02d}",
        "tipo": tipo,
        "ent": ENT[ent],
        "per": PER[per_key][0],
        "arquivo": arquivo or f"{tipo}.pdf",
        "linhas": [],
    }
    docs.append(d)
    return d


def L(d, chave, valor, secao=None, per_col=None, ent_col=None, unidade="milhar", conf=0.96,
      canon=None, moeda=None, texto=None):
    d["linhas"].append((chave, valor, secao, per_col, ent_col, unidade, conf, canon, moeda, texto))


def escreve_balanco(d, ent, anos):
    """A estrutura que `render.tabela_bp` imprime: grupo → seção → subseção →
    conta, com o total de cada nível.

    AS ARMADILHAS 1, 2, 7 e 10 ENTRAM AQUI SOZINHAS, porque vêm do plano de
    contas do book e não de um enfeite deste arquivo: conta que nasce em 2024
    (antecipação de recebíveis) ou em 2025 (parcelamento) simplesmente não tem
    linha nos anos anteriores — **célula vazia não é zero, e a ausência é a
    forma fiel de dizer isso**; o mesmo saldo troca de nome entre 2024 e 2025;
    cada empresa chama o disponível de um jeito; e as redutoras já vêm com sinal
    negativo do motor.
    """
    for ano in anos:
        pc, t = str(ano), tot[ano][ent]
        L(d, "ATIVO", t["ATIVO"], SEC_ATIVO, pc, canon=NC)
        for sec, lab in [("AC", "Ativo Circulante"), ("ANC", "Ativo Não Circulante")]:
            L(d, lab, t[sec], SEC_ATIVO, pc, canon=CANON_BP[sec])
            for sub, contas in bp[ano][ent][sec].items():
                if not contas:
                    continue
                L(d, sub, sum(v for _, v in contas), lab, pc, canon=CANON_BP[sec])
                for rot, v in contas:
                    L(d, rot, v, sub, pc, canon=CANON_BP[sec])
        L(d, "TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO, pc, canon=NC)
        L(d, SEC_PASSIVO, t["PASSIVO_PL"], SEC_PASSIVO, pc, canon=NC)
        for sec, lab in [("PC", "Passivo Circulante"), ("PNC", "Passivo Não Circulante"),
                         ("PL", "Patrimônio Líquido")]:
            L(d, lab, t[sec], SEC_PASSIVO, pc, canon=CANON_BP[sec])
            for sub, contas in bp[ano][ent][sec].items():
                if not contas:
                    continue
                L(d, sub, sum(v for _, v in contas), lab, pc, canon=CANON_BP[sec])
                for rot, v in contas:
                    L(d, rot, v, sub, pc, canon=CANON_BP[sec])
        L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, pc, canon=NC)


# ------------------------------------------------------------- 01-06: BALANÇOS
# A Indústria traz os TRÊS exercícios num documento só (é o comparativo que o
# nome do arquivo anuncia); as demais trazem dois ou um, como o cliente manda.
escreve_balanco(doc(1, "BALANCO", "industria", "multi_232425",
                    "01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf"),
                "industria", [2025, 2024, 2023])
escreve_balanco(doc(2, "BALANCO", "comercial", "multi_2425",
                    "06_Balanco_Patrimonial_Canastra_Comercial_2025x2024.pdf"),
                "comercial", [2025, 2024])
escreve_balanco(doc(3, "BALANCO", "transportes", "anual_2025",
                    "09_Balanco_CN_Transportes_2025.pdf"), "transportes", [2025])
escreve_balanco(doc(4, "BALANCO", "agro", "anual_2025",
                    "12_Balanco_Agroflorestal_2025.pdf"), "agro", [2025])
escreve_balanco(doc(5, "BALANCO", "imob", "anual_2025",
                    "Doc1.pdf"), "imob", [2025])
escreve_balanco(doc(6, "BALANCO", "holding", "anual_2025",
                    "18_Balanco_Canastra_Participacoes_2025.pdf"), "holding", [2025])

# ----------------------------------------------------------------- 07: COMBINADO
# ARMADILHA 6, e ela é dupla. "Eliminações" ocupa uma COLUNA no quadro e não é
# uma empresa — quem tratar coluna como entidade cria uma sexta controlada com
# ativo negativo. E há NÃO CONTROLADORES (35% da CN Transportes), então
# "combinado = soma das colunas" está errado por construção: a diferença tem
# nome, valor e linha própria.
d = doc(7, "COMBINADO", "grupo", "anual_2025",
        "20_Demonstracoes_Combinadas_Grupo_Canastra_2025.pdf")
comb = M.combinado(bp, tot, 2025)
for e in D.ORDEM:
    ec, t = NOME[e], tot[2025][e]
    for chave, val, secao in [
        ("Ativo Circulante", t["AC"], SEC_ATIVO),
        ("Ativo Não Circulante", t["ANC"], SEC_ATIVO),
        ("TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO),
        ("Passivo Circulante", t["PC"], SEC_PASSIVO),
        ("Passivo Não Circulante", t["PNC"], SEC_PASSIVO),
        ("Patrimônio Líquido", t["PL"], SEC_PASSIVO),
    ]:
        L(d, chave, val, secao, "2025", ec, canon=CANON_BP_LABEL.get(chave, NC))
for rotulo, val in comb["elim"]:
    L(d, "Eliminação — " + rotulo, -val, "ELIMINAÇÕES", "2025", "Eliminações", canon=NC)
for chave, val in [("Eliminação de investimentos (MEP)", -comb["elim_invest"]),
                   ("Eliminação de mútuos e conta corrente", -comb["elim_mutuos"]),
                   ("Eliminação de provisão para passivo a descoberto", -comb["elim_provisao"])]:
    L(d, chave, val, "ELIMINAÇÕES", "2025", "Eliminações", canon=NC)
L(d, "TOTAL DO ATIVO", comb["ativo"], SEC_ATIVO, "2025", "Combinado", canon=NC)
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", comb["passivo"] + comb["pl"],
  SEC_PASSIVO, "2025", "Combinado", canon=NC)
L(d, "Participação de não controladores", comb["nci"], SEC_PASSIVO, "2025", "Combinado",
  canon="patrimonio_liquido")

# ----------------------------------------------------------------------- 08: DRE
# Os TRÊS exercícios, com o subtotal IMPRESSO COM VALOR — que é a diferença
# apontada pela rodada v46 (no book Vertentes o cabeçalho de seção vem sem
# número, e a extração real do Canastra tem de trazer os dois).
d = doc(8, "DRE", "industria", "multi_232425",
        "02_DRE_Canastra_Industria_2025x2024x2023.pdf")
dre = X.dre_industria(bp, tot)
for ano in (2025, 2024, 2023):
    secao_atual = None
    for rot, v, tipo in dre[ano]:
        if tipo in ("ancora", "subtotal"):
            secao_atual = rot
            L(d, rot, v, secao_atual, str(ano), canon=CANON_DRE.get(rot, NC))
        else:
            L(d, rot, v, secao_atual, str(ano), canon=CANON_DRE.get(secao_atual, NC))

# ----------------------------------------------------------------------- 09: DFC
d = doc(9, "FLUXO_CAIXA", "industria", "anual_2025",
        "03_DFC_Canastra_Industria_12M25.pdf")
dfc_linhas, caixa_ini, caixa_fim = X.dfc(bp, tot, 2025)
secao_atual = None
for rot, v, tipo in dfc_linhas:
    if tipo == "ancora" and rot in CANON_DFC:
        secao_atual = rot
    L(d, rot, v, secao_atual or "VARIAÇÃO DE CAIXA", "2025",
      canon=CANON_DFC.get(secao_atual, NC))

# ---------------------------------------------------------------------- 10: DMPL
# ARMADILHA 8: as linhas "SALDOS EM 31 DE DEZEMBRO DE ..." são POSIÇÃO, não
# movimentação — e agora são três (2022, 2023, 2024, 2025). Somá-las com as de
# movimento conta o patrimônio quatro vezes.
d = doc(10, "DMPL", "industria", "multi_232425",
        "04_DMPL_Canastra_Industria_2023_a_2025.pdf")
dmpl_colunas, dmpl_mov = X.dmpl(bp, tot)
for mov, valores, _tipo in dmpl_mov:
    for comp, v in zip(dmpl_colunas, valores):
        if v is None:
            continue
        L(d, comp, v, mov, "2025", canon="dmpl")

# ----------------------------------------------------------------------- 11: DVA
d = doc(11, "DVA", "industria", "anual_2025", "05_DVA_Canastra_Industria_12M25.pdf")
dva_geracao, dva_distribuicao, dva_total = X.dva(bp, tot, 2025)
for rot, v, _tipo in dva_geracao:
    L(d, rot, v, "GERAÇÃO DO VALOR ADICIONADO", "2025", canon=NC)
for rot, v in dva_distribuicao:
    L(d, rot, v, "DISTRIBUIÇÃO DO VALOR ADICIONADO", "2025", canon=NC)
L(d, "VALOR ADICIONADO TOTAL A DISTRIBUIR", dva_total, "DISTRIBUIÇÃO DO VALOR ADICIONADO",
  "2025", canon=NC)

# ------------------------------------------------ 12: MAPA DE DÍVIDA (REAIS + USD)
# ARMADILHAS 3 e 5 juntas. O documento está em REAIS (as demonstrações, em
# milhares) e uma tranche é em DÓLAR, com saldo em US$ e o equivalente em R$ lado
# a lado. Somar a coluna errada erra por ~5,4x — a mesma família do defeito que a
# `0035` corrigiu. A linha em dólar declara `moeda`, que é o campo que existe
# para isso; o equivalente em reais é a linha que a reconciliação soma.
d = doc(12, "MAPA_DIVIDA", "grupo", "base_251231",
        "22_Mapa_de_Divida_Grupo_Canastra_31122025.pdf")
contratos, divida_total, juros_total = X.mapa_divida(bp, 2025)
for ct in contratos:
    base = f"{ct['banco']} — {ct['modalidade']} — {ct['contrato']}"
    if ct["saldo_usd"]:
        L(d, base + " — saldo devedor (US$)", ct["saldo_usd"], "DÍVIDA", "2025",
          unidade="unidade", canon=NC, moeda="USD")
    L(d, base + " — saldo devedor", ct["saldo"], "DÍVIDA", "2025",
      unidade="unidade", canon=NC, moeda="BRL")
    L(d, base + " — juros do exercício", ct["juros"], "DÍVIDA", "2025",
      unidade="unidade", canon=NC, moeda="BRL")
L(d, "TOTAL — saldo devedor", divida_total, "DÍVIDA", "2025", unidade="unidade",
  canon=NC, moeda="BRL")
L(d, "TOTAL — juros do exercício", juros_total, "DÍVIDA", "2025", unidade="unidade",
  canon=NC, moeda="BRL")

# --------------------------------------------------------- 13: FATURAMENTO 36M
# Trinta e seis meses, em REAIS. A série é mensal: `fn_papel_linha` a marca como
# `serie_mensal` para o modelo não projetar mês como se fosse conta de balanço.
d = doc(13, "FATURAMENTO_24M", "industria", "l36m",
        "23_Faturamento_Mensal_Canastra_Industria_36_meses.pdf")
fat_linhas, fat_totais = X.faturamento_36m()
for ano, mes, v, _clientes, _ticket in fat_linhas:
    L(d, f"{mes}/{ano}", v, "FATURAMENTO MENSAL", str(ano), unidade="unidade", canon=NC)
for ano, v in fat_totais.items():
    L(d, "TOTAL DO EXERCÍCIO", v, "FATURAMENTO MENSAL", str(ano), unidade="unidade", canon=NC)

# ------------------------------------------------------------------- 14: MÚTUOS
# ARMADILHA 11, e é a ÚNICA divergência do book: a planilha traz R$ 240 mil a
# MENOS que o balanço. Ela tem de aparecer para o humano — é o acerto da `0117`,
# e o motivo de este documento não poder faltar na fixture.
d = doc(14, "MUTUOS", "grupo", "anual_2025",
        "24_Planilha_de_Mutuos_Intragrupo_2025.pdf")
mut_planilha, mut_total_planilha, mut_total_balanco = X.mutuos(bp, tot, 2025)
# A `secao` É O TÍTULO IMPRESSO, e essa escolha não é cosmética.
#
# O quadro do book (`render.pdf_mutuos`) é uma tabela plana de três colunas —
# "Mutuante | Mutuária | Saldo devedor" — sob o título "RELAÇÃO DE MÚTUOS ENTRE
# PARTES RELACIONADAS". Não há cabeçalho de seção DENTRO dela, então a `secao`
# livre que a extração preenche ("agrupador livre, rótulo do próprio documento")
# é o título. E **a palavra "mútuo" não aparece em nenhuma linha** — ela está no
# título e nos nomes das colunas, que é onde uma planilha de verdade a põe.
#
# Escrever "— Mútuo" no rótulo de cada linha, como o fixture de Vertentes faz,
# seria inventar um dado que o papel não tem — e foi esse enfeite que escondeu o
# defeito que este fixture achou (ver a `0123`).
SEC_MUT = "RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS"
for credor, devedor, val in mut_planilha:
    L(d, f"{credor} → {devedor}", val, SEC_MUT, "2025", canon=NC)
L(d, "TOTAL", mut_total_planilha, SEC_MUT, "2025", canon=NC)

# ------------------------------------------------------------ 15: FAT. INTRAGRUPO
# As linhas intragrupo que NÃO são mútuo: fornecimento, aluguel e frete entre
# coligadas. Elas moram na mesma família da planilha de mútuos e casam com contas
# DIFERENTES do balanço, uma a uma.
d = doc(15, "FAT_INTRAGRUPO", "grupo", "multi_232425",
        "25_Faturamento_Intragrupo_2023_a_2025.pdf")
for ano, linhas in X.faturamento_intragrupo(bp):
    for emissor, tomador, natureza, val in linhas:
        L(d, f"{emissor} → {tomador} — {natureza}", val, "FATURAMENTO INTRAGRUPO",
          str(ano), canon=NC)

# ---------------------------------------------------------------- 16-17: AGING
# ARMADILHA 4: o aging de PAGÁVEIS sai de um ERP em locale en-US, com separador
# decimal anglo (`1,234.56`). O extrator devolve NÚMERO — trocar ponto por
# vírgula sem olhar erra por 1.000x, e é isso que o assert de ordem de grandeza
# cobra do dado gravado.
ar_linhas, ar_total, ar_vencido = X.aging_recebiveis(bp, 2025)
d = doc(16, "AGING_AR", "industria", "base_251231",
        "26_Aging_Contas_a_Receber_Canastra_Industria_31122025.pdf")
for cliente, faixas, total in ar_linhas:
    for faixa, v in zip(X.FAIXAS_AR, faixas):
        L(d, cliente, v, faixa, "2025", canon=NC)
    L(d, cliente, total, "Total", "2025", canon=NC)
L(d, "TOTAL GERAL", ar_total, "AGING DE RECEBÍVEIS", "2025", canon=NC)
L(d, "TOTAL VENCIDO", ar_vencido, "AGING DE RECEBÍVEIS", "2025", canon=NC)

ap_linhas, ap_total, ap_vencido = X.aging_pagaveis(bp, 2025)
d = doc(17, "AGING_AP", "industria", "base_251231",
        "digitalizado_20260114_contas_a_pagar.pdf")
for fornecedor, faixas, total in ap_linhas:
    for faixa, v in zip(X.FAIXAS_AP, faixas):
        L(d, fornecedor, v, faixa, "2025", canon=NC)
    L(d, fornecedor, total, "Total", "2025", canon=NC)
L(d, "TOTAL GERAL", ap_total, "AGING DE PAGÁVEIS", "2025", canon=NC)
L(d, "TOTAL VENCIDO", ap_vencido, "AGING DE PAGÁVEIS", "2025", canon=NC)

# ---------------------------------------------------------------- 18: ESTOQUES
# ARMADILHA 3, terceira escala: o documento traz QUANTIDADE FÍSICA ao lado do
# valor. `unidade` diz qual é qual — uma tonelada somada a um real vira número
# sem significado, e não há como saber depois.
d = doc(18, "ESTOQUE", "industria", "base_251231",
        "27_Posicao_de_Estoques_31122025.pdf")
est_grupos, est_provisao, est_total = X.estoques(bp, 2025)
for grupo_nome, itens, subtotal in est_grupos:
    for item, un, qtd, _valor_unit, valor in itens:
        # DUAS COLUNAS NUMÉRICAS, DUAS UNIDADES. A quantidade física entra com a
        # sua unidade real ('t'); o valor, em milhar. Quem somar as duas colunas
        # produz número sem significado, e depois não há como saber qual era qual.
        L(d, item, qtd, grupo_nome + " — Quantidade", "2025", unidade=un, canon=NC)
        L(d, item, valor, grupo_nome, "2025", canon=NC)
    L(d, grupo_nome, subtotal, "ESTOQUES", "2025", canon=NC)
L(d, "(-) Provisão para obsolescência", est_provisao, "ESTOQUES", "2025", canon=NC)
L(d, "TOTAL DE ESTOQUES", est_total, "ESTOQUES", "2025", canon=NC)

# ---------------------------------------------------------- 19: SITUAÇÃO FISCAL
d = doc(19, "SITUACAO_FISCAL", "industria", "base_251231",
        "28_Situacao_Fiscal_e_Parcelamentos_Canastra_Industria.pdf")
parcelamentos, correntes, provisoes_trib, tot_parc, tot_corr = X.situacao_fiscal(bp, 2025)
for pa in parcelamentos:
    base = f"{pa['entidade']} — {pa['programa']}"
    L(d, base + " — saldo circulante", pa["saldo_cp"], "PARCELAMENTOS", "2025",
      canon="passivo_circulante")
    L(d, base + " — saldo não circulante", pa["saldo_lp"], "PARCELAMENTOS", "2025",
      canon="passivo_nao_circulante")
L(d, "TOTAL DE PARCELAMENTOS", tot_parc, "PARCELAMENTOS", "2025", canon=NC)
for rot, v in correntes:
    L(d, rot, v, "TRIBUTOS CORRENTES", "2025", canon=NC)
L(d, "TOTAL DE TRIBUTOS CORRENTES", tot_corr, "TRIBUTOS CORRENTES", "2025", canon=NC)

# ------------------------------------------------------------ 20: CONTINGÊNCIAS
# ARMADILHA 9: somar provável + possível + remoto infla o passivo. A `secao`
# carrega o PROGNÓSTICO, que é o que separa o que está provisionado no balanço do
# que é só divulgação em nota.
d = doc(20, "CONTINGENCIAS", "grupo", "base_251231",
        "ANEXO IV - contingencias e processos.pdf")
cont_linhas, cont_provisionado, cont_possivel, cont_remoto = X.contingencias(bp, 2025)
for natureza, descricao, prognostico, valor, _provisionado in cont_linhas:
    L(d, f"{natureza} — {descricao}", valor, f"CONTINGÊNCIAS — {prognostico}", "2025", canon=NC)
L(d, "TOTAL PROVISIONADO (provável)", cont_provisionado, "CONTINGÊNCIAS — Provável",
  "2025", canon=NC)
L(d, "TOTAL (possível)", cont_possivel, "CONTINGÊNCIAS — Possível", "2025", canon=NC)
L(d, "TOTAL (remoto)", cont_remoto, "CONTINGÊNCIAS — Remoto", "2025", canon=NC)

# ------------------------------------------------------------- 21: IMOBILIZADO
# É UMA MATRIZ, e a forma fiel de extraí-la é a mesma da DMPL: um grupo por
# COLUNA, com `secao` = o nome da coluna e `chave` = a classe do bem. Escrever
# "Terrenos — custo" no rótulo colaria a coluna dentro do nome da conta, e aí o
# mesmo bem passaria a ter três rótulos que nenhuma outra peça reconhece.
#
# O TIPO É `NOTAS_EXPL` E ISSO É UMA LACUNA ANOTADA, não uma escolha boa: a
# taxonomia (`Supabase/migrations/0002`) não tem tipo para anexo de composição de
# imobilizado — conferi. `DF_AUDITADA` seria pior, porque põe o anexo na lista de
# peças que a reconciliação lê como BALANÇO (o lado A dos mútuos, a duplicidade
# de rótulo), e um detalhamento não é um balanço. `NOTAS_EXPL` é o tipo cuja
# semântica bate: detalhamento complementar que acompanha a DF e NÃO pode ser
# somado debaixo do total que o balanço já informa.
d = doc(21, "NOTAS_EXPL", "industria", "base_251231",
        "29_Composicao_do_Imobilizado_31122025.pdf")
imo_linhas, imo_custo, imo_dep, imo_liquido = X.imobilizado(bp, 2025)
for classe, custo, _taxa, dep, liquido in imo_linhas:
    L(d, classe, custo, "Custo", "2025", canon="ativo_nao_circulante")
    L(d, classe, dep, "Depreciação acumulada", "2025", canon="ativo_nao_circulante")
    L(d, classe, liquido, "Valor líquido", "2025", canon="ativo_nao_circulante")
L(d, "TOTAL", imo_custo, "Custo", "2025", canon="ativo_nao_circulante")
L(d, "TOTAL", imo_dep, "Depreciação acumulada", "2025", canon="ativo_nao_circulante")
L(d, "TOTAL", imo_liquido, "Valor líquido", "2025", canon="ativo_nao_circulante")

# ------------------------------------------------------------------ 22: FOLHA
# ARMADILHA 3, quarta escala: HEADCOUNT é em PESSOAS. Multiplicar por mil porque
# "o caso está em milhares" cria uma fábrica com 412.000 empregados.
d = doc(22, "HEADCOUNT", "industria", "base_251231",
        "30_Headcount_e_Folha_Canastra_Industria.pdf")
folha_linhas, headcount, folha_anual = X.folha(2025)
for area, pessoas, _salario_medio, custo_mes, _custo_ano in folha_linhas:
    L(d, area, pessoas, "Headcount", "2025", unidade="pessoas", canon=NC)
    L(d, area, custo_mes, "Custo mensal", "2025", canon=NC)
L(d, "TOTAL", headcount, "Headcount", "2025", unidade="pessoas", canon=NC)
L(d, "TOTAL", folha_anual, "Custo anual", "2025", canon=NC)

# --------------------------------------------------------- 23: EXTRATO BANCÁRIO
d = doc(23, "EXTRATO_BANCARIO", "industria", "base_251231",
        "31_Extratos_Bancarios_31122025.pdf")
extrato_linhas, extrato_total = X.extratos(bp, 2025)
for banco, agencia, conta, _tipo_conta, saldo in extrato_linhas:
    L(d, f"{banco} — ag. {agencia} c/c {conta}", saldo, "SALDOS BANCÁRIOS", "2025", canon=NC)
L(d, "TOTAL", extrato_total, "SALDOS BANCÁRIOS", "2025", canon=NC)

# ---------------------------------------------------------------- 24: BALANCETE
d = doc(24, "BALANCETE", "industria", "anual_2025",
        "32_Balancete_Analitico_Canastra_Industria_12M25.pdf")
bal_linhas = X.balancete(bp, 2025, "industria")
for codigo, rot, valor, natureza in bal_linhas:
    # ARMADILHA 10 na sua forma de balancete: quem dá o SINAL aqui é a coluna
    # D/C, não o parêntese. Conta credora com valor positivo na coluna é saldo
    # NEGATIVO no balanço — ler a coluna de valor sozinha inverte o passivo
    # inteiro.
    secao_lab, canon, _esperada = _do_codigo(codigo)
    L(d, rot, _valor_do_balancete(codigo, valor, natureza), secao_lab, "2025", canon=canon)
t = tot[2025]["industria"]
L(d, "TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO, "2025", canon=NC)
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, "2025", canon=NC)

# ------------------------------------------------------------------- 25: RAZÃO
d = doc(25, "RAZAO", "industria", "anual_2025",
        "33_Livro_Razao_Fornecedores_Nacionais_12M25.pdf")
razao_linhas, razao_ini, razao_deb, razao_cred, razao_fim = X.razao_fornecedores(bp, 2025)
L(d, "SALDO ANTERIOR", razao_ini, "RAZÃO — Fornecedores nacionais", "2025",
  canon="passivo_circulante")
for data, lancamento, historico, debito, credito, saldo, _dc in razao_linhas:
    L(d, f"{data} — {lancamento} — {historico}", saldo, "RAZÃO — Fornecedores nacionais",
      "2025", canon="passivo_circulante")
L(d, "TOTAL DE DÉBITOS", razao_deb, "RAZÃO — Fornecedores nacionais", "2025",
  canon="passivo_circulante")
L(d, "TOTAL DE CRÉDITOS", razao_cred, "RAZÃO — Fornecedores nacionais", "2025",
  canon="passivo_circulante")
L(d, "SALDO FINAL", razao_fim, "RAZÃO — Fornecedores nacionais", "2025",
  canon="passivo_circulante")

# ------------------------------------------------ 26-28: DOCUMENTOS SEM NÚMERO
# ARMADILHA 12: certidão, organograma e contrato social não podem gerar linha
# financeira. Zero campo NÃO é falha de extração aqui — é o resultado certo, e a
# `0111` é quem sabe disso. Eles entram na fixture justamente para que o assert
# de "todo documento produziu linha" NÃO os cobre.
doc(26, "CERTIDOES", "industria", "base_251231",
    "34_Certidao_Negativa_de_Debitos_Canastra_Industria.pdf")
doc(27, "ORGANOGRAMA", "grupo", "base_251231",
    "35_Organograma_Societario_Grupo_Canastra.pdf")
doc(28, "CONTRATO_SOCIAL", "industria", "base_251231",
    "36_Contrato_Social_Consolidado_Canastra_Industria.pdf")

# ---------------------------------------------------------------------- emitir
out = [
    "-- GERADO por Supabase/test/gerar_fixture_canastra.py — não editar à mão.",
    "-- Extração FIEL dos documentos de Dados de Teste/book-canastra (o book DIFÍCIL).",
    "-- Cenário: documento difícil + extração fiel => a única pendência legítima é a",
    "-- divergência de R$ 240 mil que a planilha de mútuos planta de propósito.",
    "begin;",
    "delete from caso where id = " + CASO + ";",
    f"insert into caso (id, nome, produto) values ({CASO}, 'FIXTURE Grupo Canastra', 'reestruturacao');",
]
for k, u in ENT.items():
    out.append(
        "insert into entidade (id, caso_id, razao_social, papel_no_grupo) values "
        f"('{u}', {CASO}, {q(NOME[k])}, '{PAPEL[k]}');")
for u, tipo, ref in PER.values():
    out.append(
        "insert into periodo (id, caso_id, tipo, referencia) values "
        f"('{u}', {CASO}, {q(tipo)}, {q(ref)});")
for d in docs:
    out.append(
        "insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte) "
        f"values ('{d['doc']}', {CASO}, '{d['ent']}', '{d['per']}', {q(d['tipo'])}, 'valido', 0.96, 'fixture');")
    out.append(
        "insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash) "
        f"values ('{d['ver']}', '{d['doc']}', 1, 'fixture/{d['doc']}.pdf', "
        f"{q(d['arquivo'])}, md5('{d['doc']}'));")
    vals = [
        f"('{d['ver']}', {q(k)}, {n(v)}, {q(u)}, {n(cf)}, {q(s)}, {q(ca)}, {q(pcol)}, "
        f"{q(ecol)}, {q(mo)}, {i}, 'aceito')"
        for i, (k, v, s, pcol, ecol, u, cf, ca, mo, _tx) in enumerate(d["linhas"])
    ]
    for i in range(0, len(vals), 150):
        out.append(
            "insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca, "
            "secao, secao_canonica, periodo_coluna, entidade_coluna, moeda, ordem, status_aceite) values\n  "
            + ",\n  ".join(vals[i:i + 150]) + ";")
out.append("commit;")

if "--json" in sys.argv:
    TIPO_PER = {v[0]: {"tipo": v[1], "referencia": v[2]} for v in PER.values()}
    UUID_NOME = {u: NOME[k] for k, u in ENT.items()}
    sys.stdout.write(json.dumps({
        "documentos": [
            {
                "id": d["doc"],
                "tipo_taxonomia": d["tipo"],
                "entidade": {"razao_social": UUID_NOME[d["ent"]]},
                "periodo": TIPO_PER[d["per"]],
                "documento_versao": [{"id": d["ver"], "nome_original": d["arquivo"]}],
            }
            for d in docs
        ],
        "campos": [
            {
                "id": f"{d['ver']}-{i}",
                "documento_versao_id": d["ver"],
                "chave": k, "valor_num": v, "secao": sec, "secao_canonica": ca,
                "ordem": i,
                "entidade_coluna": ecol, "periodo_coluna": pcol,
                "valor_texto": tx, "unidade": u, "confianca": cf, "origem_pagina": 1,
                "moeda": mo,
                "status_aceite": "aceito", "aceito_por": "fixture",
                "aceito_em": "2026-08-19T00:00:00Z",
            }
            for d in docs
            for i, (k, v, sec, pcol, ecol, u, cf, ca, mo, tx) in enumerate(d["linhas"])
        ],
    }, ensure_ascii=False))
else:
    sys.stdout.write("\n".join(out) + "\n")
