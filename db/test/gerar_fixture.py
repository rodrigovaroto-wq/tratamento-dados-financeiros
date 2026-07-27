# -*- coding: utf-8 -*-
"""Gera `fixture_book_vertentes.sql` a partir do gerador do book.

O fixture representa uma extração PERFEITA dos 14 documentos de
`test-data/book-vertentes` — é o cenário em que o dono diz "o arquivo foi 100%
extraído e com extrema qualidade". Nesse cenário a reconciliação **não deve
abrir nenhuma pendência**: as únicas divergências legítimas do book são as
armadilhas deliberadas (mútuos R$ 180 mil), e as escalas mistas (mapa de dívida
em reais × demonstrações em milhares) devem ser CONVERTIDAS, não recusadas.

Uso (de dentro de test-data/book-vertentes, que é onde os módulos do book vivem):

    cd test-data/book-vertentes
    python3 ../../db/test/gerar_fixture.py > ../../db/test/fixture_book_vertentes.sql

O `.sql` gerado é versionado para que `db/test/run.sh` rode sem Python.
"""
import sys

import dados as D
import demonstracoes as X
import motor as M

bp, tot = M.construir()
l25, v24, _alvo = X.dre_metalurgica(tot)
c25, prejuizo = X.cascata(l25)
c24, _res24 = X.cascata(l25, v24)
receita_bruta = sum(v for r, v, t in c25 if t == "conta" and r.startswith(("Vendas", "Prestação")))
desp_fin = [v for r, v, t in c25 if r.startswith("(-) Despesas financeiras")][0]
fat, t24f, t25f = X.faturamento_24m(receita_bruta)
contratos = X.mapa_divida(desp_fin)
dfc = X.dfc_metalurgica(tot, prejuizo)

CASO = "'11111111-1111-1111-1111-111111111111'"
ENT = {
    "metalurgica": "22222222-0000-0000-0000-000000000001",
    "componentes": "22222222-0000-0000-0000-000000000002",
    "holding": "22222222-0000-0000-0000-000000000003",
    "logistica": "22222222-0000-0000-0000-000000000004",
    "spe": "22222222-0000-0000-0000-000000000005",
    "grupo": "22222222-0000-0000-0000-000000000006",
}
NOME = {k: D.ENTIDADES[k]["razao_social"] for k in D.ENTIDADES}
NOME["grupo"] = D.GRUPO

# Cada arquivo declara a granularidade de período que quer — é essa variação que
# a reconciliação tem de tolerar (nome do arquivo "2025x2024" vira multi;
# "Posição em 31/12/2025" vira data-base; faturamento de 24 meses vira L24M).
PER = {
    "multi_2425": ("33333333-0000-0000-0000-000000000001", "multi", "24,25"),
    "anual_2025": ("33333333-0000-0000-0000-000000000002", "anual", "2025"),
    "base_251231": ("33333333-0000-0000-0000-000000000004", "data-base", "2025-12-31"),
    "l24m": ("33333333-0000-0000-0000-000000000005", "L24M", "24,25"),
}

SEC_ATIVO = "ATIVO"
SEC_PASSIVO = "PASSIVO E PATRIMÔNIO LÍQUIDO"


def q(s):
    return "null" if s is None else "'" + str(s).replace("'", "''") + "'"


def n(v):
    return "null" if v is None else repr(float(v))


docs = []


def doc(idx, tipo, ent, per_key):
    d = {
        "doc": f"44444444-0000-0000-0000-0000000000{idx:02d}",
        "ver": f"55555555-0000-0000-0000-0000000000{idx:02d}",
        "tipo": tipo,
        "ent": ENT[ent],
        "per": PER[per_key][0],
        "linhas": [],
    }
    docs.append(d)
    return d


def L(d, chave, valor, secao=None, per_col=None, ent_col=None, unidade="milhar", conf=0.97):
    d["linhas"].append((chave, valor, secao, per_col, ent_col, unidade, conf))


# --------------------------------------------------------------- 01-05: BALANÇOS
# Estrutura exatamente como `render.tabela_bp` imprime: grupo (ATIVO) → seção
# (Ativo Circulante) → subseção (Disponível) → conta, e a linha TOTAL DO ATIVO.
for ent, idx in [("metalurgica", 1), ("componentes", 2), ("holding", 3),
                 ("logistica", 4), ("spe", 5)]:
    d = doc(idx, "BALANCO", ent, "multi_2425")
    for ano in (2025, 2024):
        pc, t = str(ano), tot[ano][ent]
        L(d, "ATIVO", t["ATIVO"], SEC_ATIVO, pc)
        for sec, lab in [("AC", "Ativo Circulante"), ("ANC", "Ativo Não Circulante")]:
            L(d, lab, t[sec], SEC_ATIVO, pc)
            for sub, contas in bp[ano][ent][sec].items():
                if not contas:
                    continue
                L(d, sub, sum(v for _, v in contas), lab, pc)
                for rot, v in contas:
                    L(d, rot, v, sub, pc)
        L(d, "TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO, pc)
        L(d, SEC_PASSIVO, t["PASSIVO_PL"], SEC_PASSIVO, pc)
        for sec, lab in [("PC", "Passivo Circulante"), ("PNC", "Passivo Não Circulante"),
                         ("PL", "Patrimônio Líquido")]:
            L(d, lab, t["PL"] if sec == "PL" else t[sec], SEC_PASSIVO, pc)
            for sub, contas in bp[ano][ent][sec].items():
                if not contas:
                    continue
                L(d, sub, sum(v for _, v in contas), lab, pc)
                for rot, v in contas:
                    L(d, rot, v, sub, pc)
        L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, pc)

# ------------------------------------------------------------------- 06: COMBINADO
d = doc(6, "COMBINADO", "grupo", "anual_2025")
c = M.combinado(bp, tot, 2025)
for e in ["componentes", "spe", "metalurgica", "holding", "logistica"]:
    ec, t = NOME[e], tot[2025][e]
    for chave, val, secao in [
        ("Ativo Circulante", t["AC"], SEC_ATIVO),
        ("Ativo Não Circulante", t["ANC"], SEC_ATIVO),
        ("TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO),
        ("Passivo Circulante", t["PC"], SEC_PASSIVO),
        ("Passivo Não Circulante", t["PNC"], SEC_PASSIVO),
        ("Patrimônio Líquido", t["PL"], SEC_PASSIVO),
    ]:
        L(d, chave, val, secao, "2025", ec)
for chave, val in [("Eliminação de investimentos (MEP)", -c["elim_invest"]),
                   ("Eliminação de mútuos e conta corrente", -c["elim_mutuos"]),
                   ("Eliminação de provisão para passivo a descoberto", -c["elim_provisao"])]:
    L(d, chave, val, "ELIMINAÇÕES", "2025", "Eliminações")
L(d, "TOTAL DO ATIVO", c["ativo"], SEC_ATIVO, "2025", "Combinado")
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", c["passivo"] + c["pl"], SEC_PASSIVO, "2025", "Combinado")
L(d, "Participação de não controladores", c["nci"], SEC_PASSIVO, "2025", "Combinado")

# ------------------------------------------------------------------------ 07: DRE
# "RECEITA OPERACIONAL BRUTA" é CABEÇALHO SEM VALOR (convenção BR comum): quem
# quiser a receita bruta tem de somar as contas da seção.
d = doc(7, "DRE", "metalurgica", "multi_2425")
for cascata, ano in ((c25, "2025"), (c24, "2024")):
    secao_atual = None
    for rot, v, tipo in cascata:
        if tipo == "sub":
            secao_atual = rot
            L(d, rot, None, secao_atual, ano)
        else:
            L(d, rot, v, secao_atual, ano)

# ------------------------------------------------------------------------ 08: DFC
d = doc(8, "FLUXO_CAIXA", "metalurgica", "anual_2025")
for grupo_lab, chave_tot, itens in [
    ("FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS", "tot_op", dfc["operacional"]),
    ("FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO", "tot_inv", dfc["investimento"]),
    ("FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO", "tot_fin", dfc["financiamento"]),
]:
    L(d, grupo_lab, None, grupo_lab, "2025")
    for rot, v in itens:
        L(d, rot, v, grupo_lab, "2025")
    L(d, "Caixa líquido gerado pelas (aplicado nas) " + grupo_lab.split("DAS ")[1].lower(),
      dfc[chave_tot], grupo_lab, "2025")
L(d, "REDUÇÃO LÍQUIDA DE CAIXA E EQUIVALENTES DE CAIXA", dfc["variacao"], "VARIAÇÃO DE CAIXA", "2025")
L(d, "Caixa e equivalentes de caixa no início do exercício", dfc["caixa_ini"], "VARIAÇÃO DE CAIXA", "2025")
L(d, "Caixa e equivalentes de caixa no final do exercício", dfc["caixa_fim"], "VARIAÇÃO DE CAIXA", "2025")

# ---------------------------------------------------------------- 10: FATURAMENTO
d = doc(10, "FATURAMENTO_24M", "metalurgica", "l24m")
for mes, v2024, v2025 in fat:
    L(d, f"{mes}/2024", v2024, "FATURAMENTO MENSAL", "2024")
    L(d, f"{mes}/2025", v2025, "FATURAMENTO MENSAL", "2025")
L(d, "TOTAL DO EXERCÍCIO", t24f, "FATURAMENTO MENSAL", "2024")
L(d, "TOTAL DO EXERCÍCIO", t25f, "FATURAMENTO MENSAL", "2025")

# ------------------------------------------------------- 11: MAPA DE DÍVIDA (REAIS)
# Armadilha deliberada do book: este documento está em REAIS, as demonstrações em
# milhares. A reconciliação tem de CONVERTER pela escala declarada.
d = doc(11, "MAPA_DIVIDA", "metalurgica", "base_251231")
for credor, mod, saldo_mil, _taxa, _venc, _gar, juros_mil in contratos:
    L(d, f"{credor} — {mod} — saldo devedor", saldo_mil * 1000, "DÍVIDA", "2025", unidade="unidade")
    L(d, f"{credor} — {mod} — juros do exercício", juros_mil * 1000, "DÍVIDA", "2025", unidade="unidade")
L(d, "TOTAL — saldo devedor", sum(c[2] for c in contratos) * 1000, "DÍVIDA", "2025", unidade="unidade")
L(d, "TOTAL — juros do exercício", sum(c[6] for c in contratos) * 1000, "DÍVIDA", "2025", unidade="unidade")

# ------------------------------------------------------------------ 13: BALANCETE
d = doc(13, "BALANCETE", "componentes", "anual_2025")
t = tot[2025]["componentes"]
for sec, lab, secao in [("AC", "Ativo Circulante", SEC_ATIVO),
                        ("ANC", "Ativo Não Circulante", SEC_ATIVO),
                        ("PC", "Passivo Circulante", SEC_PASSIVO),
                        ("PNC", "Passivo Não Circulante", SEC_PASSIVO),
                        ("PL", "Patrimônio Líquido", SEC_PASSIVO)]:
    L(d, lab, t["PL"] if sec == "PL" else t[sec], secao, "2025")
    for sub, contas in bp[2025]["componentes"][sec].items():
        for rot, v in contas:
            L(d, rot, v, lab, "2025")
L(d, "TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO, "2025")
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, "2025")

# ----------------------------------------------------------------------- emitir
out = [
    "-- GERADO por db/test/gerar_fixture.py — não editar à mão.",
    "-- Extração FIEL dos 14 documentos de test-data/book-vertentes.",
    "-- Cenário: extração perfeita => a reconciliação não deve abrir NENHUMA pendência.",
    "begin;",
    "delete from caso where id = " + CASO + ";",
    f"insert into caso (id, nome, produto) values ({CASO}, 'FIXTURE Grupo Vertentes', 'reestruturacao');",
]
for k, u in ENT.items():
    out.append(f"insert into entidade (id, caso_id, razao_social, papel_no_grupo) values ('{u}', {CASO}, {q(NOME[k])}, 'alvo');")
for u, tipo, ref in PER.values():
    out.append(f"insert into periodo (id, caso_id, tipo, referencia) values ('{u}', {CASO}, {q(tipo)}, {q(ref)});")
for d in docs:
    out.append(
        "insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte) "
        f"values ('{d['doc']}', {CASO}, '{d['ent']}', '{d['per']}', {q(d['tipo'])}, 'valido', 0.97, 'fixture');")
    out.append(
        "insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash) "
        f"values ('{d['ver']}', '{d['doc']}', 1, 'fixture/{d['doc']}.pdf', "
        f"'{d['tipo']}.pdf', md5('{d['doc']}'));")
    vals = [
        f"('{d['ver']}', {q(k)}, {n(v)}, {q(u)}, {n(cf)}, {q(s)}, {q(pcol)}, {q(ecol)}, 'aceito')"
        for k, v, s, pcol, ecol, u, cf in d["linhas"]
    ]
    for i in range(0, len(vals), 150):
        out.append(
            "insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca, "
            "secao, periodo_coluna, entidade_coluna, status_aceite) values\n  "
            + ",\n  ".join(vals[i:i + 150]) + ";")
out.append("commit;")
sys.stdout.write("\n".join(out) + "\n")
