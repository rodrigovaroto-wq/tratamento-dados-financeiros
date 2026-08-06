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

Com `--json` emite os mesmos dados em JSON, para o verificador do export
(`portal/scripts/verificar-export.mts`) montar a planilha a partir do MESMO
fixture e conferir cada seção contra o gabarito do book.
"""
import json
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


def L(d, chave, valor, secao=None, per_col=None, ent_col=None, unidade="milhar", conf=0.97,
      canon=None):
    d["linhas"].append((chave, valor, secao, per_col, ent_col, unidade, conf, canon))


# ---------------------------------------------------------------------------
# `secao_canonica` — POR QUE ELA PASSOU A SER EMITIDA AQUI.
#
# Este fixture representa uma extração PERFEITA, e até a sessão 40 ele gravava
# `secao_canonica = NULL` nas 767 linhas. A extração de verdade PREENCHE esse
# campo (é a instrução `secao_canonica` do `SYSTEM_PROMPT` em `n8n/lib/extract.mjs`,
# com o enum de `SECAO_CANONICA_ENUM`), e é ele que diz a que BLOCO do modelo cada
# conta pertence.
#
# O custo de não emitir, medido na sessão 40: no export gerado pela cadeia do book,
# `blocoDaLinha` devolvia `fora` para as 132 contas de balanço e DRE, e o modelo
# institucional saía com a DRE INTEIRA EM ZERO. Nenhuma base local conseguia provar
# o modelo ponta a ponta — o `fixture_modelagem_v35.sql` tem `secao_canonica` mas
# `secao` nula e `ordem` alfabética; a cadeia do book tinha o inverso. O defeito de
# sinal que transformou prejuízo de 17.901 em lucro de 268.041 passou por esse vão.
#
# A CLASSIFICAÇÃO É EXPLÍCITA NO PONTO DE EMISSÃO, não inferida do rótulo depois:
# aqui o gerador SABE, ao escrever a linha, se está no ativo circulante ou no
# passivo não circulante — inferir de volta pelo nome seria reintroduzir a
# ambiguidade que a extração real resolve com julgamento contábil.
#
# `NAO_CLASSIFICAVEL` é o escape do próprio enum e é usado onde não existe valor
# honesto: total de GRUPO (o enum não tem "ativo_total"), eliminações do combinado,
# faturamento mensal, mútuos e notas explicativas. Chutar um valor ali seria pior
# que declarar que não se classifica — é a mesma doutrina do prompt.
# ---------------------------------------------------------------------------
NC = "NAO_CLASSIFICAVEL"
CANON_BP = {"AC": "ativo_circulante", "ANC": "ativo_nao_circulante",
            "PC": "passivo_circulante", "PNC": "passivo_nao_circulante",
            "PL": "patrimonio_liquido"}
CANON_BP_LABEL = {"Ativo Circulante": "ativo_circulante",
                  "Ativo Não Circulante": "ativo_nao_circulante",
                  "Passivo Circulante": "passivo_circulante",
                  "Passivo Não Circulante": "passivo_nao_circulante",
                  "Patrimônio Líquido": "patrimonio_liquido"}
# A cascata da DRE do book (ver `demonstracoes.py`): o subtotal que abre a seção é
# o que define a seção canônica das contas abaixo dele.
CANON_DRE = {
    "RECEITA OPERACIONAL BRUTA": "receita_bruta",
    "DEDUÇÕES DA RECEITA BRUTA": "receita_bruta",
    "CUSTO DOS PRODUTOS VENDIDOS": "custos",
    "DESPESAS OPERACIONAIS": "despesas_operacionais",
    "RESULTADO FINANCEIRO": "resultado_financeiro",
    "TRIBUTOS SOBRE O LUCRO": "impostos_lucro",
}
CANON_DFC = {
    "FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS": "atividades_operacionais",
    "FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO": "atividades_investimento",
    "FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO": "atividades_financiamento",
}


# --------------------------------------------------------------- 01-05: BALANÇOS
# Estrutura exatamente como `render.tabela_bp` imprime: grupo (ATIVO) → seção
# (Ativo Circulante) → subseção (Disponível) → conta, e a linha TOTAL DO ATIVO.
for ent, idx in [("metalurgica", 1), ("componentes", 2), ("holding", 3),
                 ("logistica", 4), ("spe", 5)]:
    d = doc(idx, "BALANCO", ent, "multi_2425")
    for ano in (2025, 2024):
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
            L(d, lab, t["PL"] if sec == "PL" else t[sec], SEC_PASSIVO, pc, canon=CANON_BP[sec])
            for sub, contas in bp[ano][ent][sec].items():
                if not contas:
                    continue
                L(d, sub, sum(v for _, v in contas), lab, pc, canon=CANON_BP[sec])
                for rot, v in contas:
                    L(d, rot, v, sub, pc, canon=CANON_BP[sec])
        L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, pc, canon=NC)

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
        L(d, chave, val, secao, "2025", ec, canon=CANON_BP_LABEL.get(chave, NC))
for chave, val in [("Eliminação de investimentos (MEP)", -c["elim_invest"]),
                   ("Eliminação de mútuos e conta corrente", -c["elim_mutuos"]),
                   ("Eliminação de provisão para passivo a descoberto", -c["elim_provisao"])]:
    L(d, chave, val, "ELIMINAÇÕES", "2025", "Eliminações", canon=NC)
L(d, "TOTAL DO ATIVO", c["ativo"], SEC_ATIVO, "2025", "Combinado", canon=NC)
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", c["passivo"] + c["pl"], SEC_PASSIVO, "2025", "Combinado", canon=NC)
L(d, "Participação de não controladores", c["nci"], SEC_PASSIVO, "2025", "Combinado", canon="patrimonio_liquido")

# ------------------------------------------------------------------------ 07: DRE
# "RECEITA OPERACIONAL BRUTA" é CABEÇALHO SEM VALOR (convenção BR comum): quem
# quiser a receita bruta tem de somar as contas da seção.
d = doc(7, "DRE", "metalurgica", "multi_2425")
for cascata, ano in ((c25, "2025"), (c24, "2024")):
    secao_atual = None
    for rot, v, tipo in cascata:
        if tipo == "sub":
            secao_atual = rot
            L(d, rot, None, secao_atual, ano, canon=CANON_DRE.get(rot, NC))
        else:
            # A linha de resultado da cascata ("RECEITA OPERACIONAL LÍQUIDA",
            # "LUCRO BRUTO", "PREJUÍZO LÍQUIDO DO EXERCÍCIO") não é conta de seção
            # nenhuma: é o total. `fn_papel_linha` já a marca como subtotal, e o
            # modelo a usa como ÂNCORA de conferência.
            L(d, rot, v, secao_atual, ano, canon=CANON_DRE.get(secao_atual, NC))

# ------------------------------------------------------------------------ 08: DFC
d = doc(8, "FLUXO_CAIXA", "metalurgica", "anual_2025")
for grupo_lab, chave_tot, itens in [
    ("FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS", "tot_op", dfc["operacional"]),
    ("FLUXO DE CAIXA DAS ATIVIDADES DE INVESTIMENTO", "tot_inv", dfc["investimento"]),
    ("FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO", "tot_fin", dfc["financiamento"]),
]:
    ca = CANON_DFC[grupo_lab]
    L(d, grupo_lab, None, grupo_lab, "2025", canon=ca)
    for rot, v in itens:
        L(d, rot, v, grupo_lab, "2025", canon=ca)
    L(d, "Caixa líquido gerado pelas (aplicado nas) " + grupo_lab.split("DAS ")[1].lower(),
      dfc[chave_tot], grupo_lab, "2025", canon=ca)
L(d, "REDUÇÃO LÍQUIDA DE CAIXA E EQUIVALENTES DE CAIXA", dfc["variacao"], "VARIAÇÃO DE CAIXA", "2025", canon=NC)
L(d, "Caixa e equivalentes de caixa no início do exercício", dfc["caixa_ini"], "VARIAÇÃO DE CAIXA", "2025", canon=NC)
L(d, "Caixa e equivalentes de caixa no final do exercício", dfc["caixa_fim"], "VARIAÇÃO DE CAIXA", "2025", canon=NC)

# ---------------------------------------------------------------- 10: FATURAMENTO
d = doc(10, "FATURAMENTO_24M", "metalurgica", "l24m")
for mes, v2024, v2025 in fat:
    L(d, f"{mes}/2024", v2024, "FATURAMENTO MENSAL", "2024", canon=NC)
    L(d, f"{mes}/2025", v2025, "FATURAMENTO MENSAL", "2025", canon=NC)
L(d, "TOTAL DO EXERCÍCIO", t24f, "FATURAMENTO MENSAL", "2024", canon=NC)
L(d, "TOTAL DO EXERCÍCIO", t25f, "FATURAMENTO MENSAL", "2025", canon=NC)

# ------------------------------------------------------- 11: MAPA DE DÍVIDA (REAIS)
# Armadilha deliberada do book: este documento está em REAIS, as demonstrações em
# milhares. A reconciliação tem de CONVERTER pela escala declarada.
d = doc(11, "MAPA_DIVIDA", "metalurgica", "base_251231")
for credor, mod, saldo_mil, _taxa, _venc, _gar, juros_mil in contratos:
    # O mapa de dívida é roteado pelo TIPO DO DOCUMENTO (`blocoDaLinha` vê
    # `MAPA_DIVIDA` antes da seção), então a seção canônica aqui é informativa: o
    # saldo é obrigação de curto/longo prazo indistinta neste documento, e o
    # contrato é que diz. `NAO_CLASSIFICAVEL` em vez de um chute.
    L(d, f"{credor} — {mod} — saldo devedor", saldo_mil * 1000, "DÍVIDA", "2025", unidade="unidade", canon=NC)
    L(d, f"{credor} — {mod} — juros do exercício", juros_mil * 1000, "DÍVIDA", "2025", unidade="unidade", canon=NC)
L(d, "TOTAL — saldo devedor", sum(c[2] for c in contratos) * 1000, "DÍVIDA", "2025", unidade="unidade", canon=NC)
L(d, "TOTAL — juros do exercício", sum(c[6] for c in contratos) * 1000, "DÍVIDA", "2025", unidade="unidade", canon=NC)

# ------------------------------------------------------------------ 13: BALANCETE
d = doc(13, "BALANCETE", "componentes", "anual_2025")
t = tot[2025]["componentes"]
for sec, lab, secao in [("AC", "Ativo Circulante", SEC_ATIVO),
                        ("ANC", "Ativo Não Circulante", SEC_ATIVO),
                        ("PC", "Passivo Circulante", SEC_PASSIVO),
                        ("PNC", "Passivo Não Circulante", SEC_PASSIVO),
                        ("PL", "Patrimônio Líquido", SEC_PASSIVO)]:
    L(d, lab, t["PL"] if sec == "PL" else t[sec], secao, "2025", canon=CANON_BP[sec])
    for sub, contas in bp[2025]["componentes"][sec].items():
        for rot, v in contas:
            L(d, rot, v, lab, "2025", canon=CANON_BP[sec])
L(d, "TOTAL DO ATIVO", t["ATIVO"], SEC_ATIVO, "2025", canon=NC)
L(d, "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", t["PASSIVO_PL"], SEC_PASSIVO, "2025", canon=NC)

# ----------------------------------------------------------------------- 09: DMPL
# Matriz: cada célula é uma linha, `chave` = COMPONENTE do PL e `secao` =
# MOVIMENTO — é a forma que `construirAbaDMPL` monta de volta em tabela. As
# células que o PDF imprime como "-" NÃO entram: extração fiel não inventa zero
# onde o documento não tem número (zero num modelo financeiro é um valor).
d = doc(9, "DMPL", "metalurgica", "anual_2025")
_cap, _capint, _rl, _aap = 45000, -2000, 1200, 1850
_t24m, _t25m = tot[2024]["metalurgica"], tot[2025]["metalurgica"]
for _mov, _vals in [
    ("SALDOS EM 31 DE DEZEMBRO DE 2024",
     [("Capital social", _cap), ("Capital a integralizar", _capint), ("Reserva legal", _rl),
      ("Ajuste de avaliação patrimonial", _aap), ("Prejuízos acumulados", _t24m["plug"]),
      ("Total", _t24m["PL"])]),
    ("Prejuízo líquido do exercício",
     [("Prejuízos acumulados", prejuizo), ("Total", prejuizo)]),
    ("SALDOS EM 31 DE DEZEMBRO DE 2025",
     [("Capital social", _cap), ("Capital a integralizar", _capint), ("Reserva legal", _rl),
      ("Ajuste de avaliação patrimonial", _aap), ("Prejuízos acumulados", _t25m["plug"]),
      ("Total", _t25m["PL"])]),
]:
    for _comp, _v in _vals:
        L(d, _comp, _v, _mov, "2025", canon="dmpl")

# ------------------------------------------------------------------- 12: MÚTUOS
# O documento tem a divergência DELIBERADA de R$ 180 mil contra o balanço
# (planilha de controle mantida à parte do razão) — é o caso que a reconciliação
# deve MOSTRAR, e é por isso que ele precisa estar na fixture.
mut, tot_mut = X.mutuos_intragrupo(tot)
d = doc(12, "MUTUOS", "grupo", "anual_2025")
for _cred, _dev, _nat, _val, _venc in mut:
    L(d, f"{_cred} → {_dev} — {_nat}", _val, "MÚTUOS E CONTAS INTRAGRUPO", "2025", canon=NC)
L(d, "TOTAL", tot_mut, "MÚTUOS E CONTAS INTRAGRUPO", "2025", canon=NC)

# ---------------------------------------------------------- 14: NOTAS EXPLICATIVAS
# Notas são PROSA com alguns números dentro. A extração fiel traz os números que
# o texto afirma, com a `secao` no formato de nota ("Nota 1", "Nota 2") — que
# `ehSecaoDeNotaExplicativa` reconhece para NÃO rotear essas linhas para o
# Balanço. Sem esse reconhecimento, o detalhe da nota entraria somando DEBAIXO do
# total que o BP já informa: dupla contagem vinda de documento complementar.
d = doc(14, "NOTAS_EXPL", "metalurgica", "anual_2025")
L(d, "Prejuízo líquido do exercício", abs(_t25m["plug"] - _t24m["plug"]), "Nota 1", "2025", canon=NC)
L(d, "Capital circulante líquido negativo", abs(_t25m["AC"] - _t25m["PC"]), "Nota 1", "2025", canon=NC)
L(d, "Índice de liquidez corrente", round(_t25m["AC"] / _t25m["PC"], 2), "Nota 1", "2025",
  unidade=None, canon=NC)
L(d, "Parcela reclassificada de longo para curto prazo (covenant)",
  bp[2025]["metalurgica"]["PC"][ "Empréstimos e Financiamentos"][0][1]
  if "Empréstimos e Financiamentos" in bp[2025]["metalurgica"]["PC"] else 0,
  "Nota 2", "2025", canon=NC)

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
        f"('{d['ver']}', {q(k)}, {n(v)}, {q(u)}, {n(cf)}, {q(s)}, {q(ca)}, {q(pcol)}, {q(ecol)}, 'aceito')"
        for k, v, s, pcol, ecol, u, cf, ca in d["linhas"]
    ]
    for i in range(0, len(vals), 150):
        out.append(
            "insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca, "
            "secao, secao_canonica, periodo_coluna, entidade_coluna, status_aceite) values\n  "
            + ",\n  ".join(vals[i:i + 150]) + ";")
out.append("commit;")

if "--json" in sys.argv:
    # Mesmo fixture, formato que o verificador do export consome.
    TIPO_PER = {v[0]: {"tipo": v[1], "referencia": v[2]} for v in PER.values()}
    UUID_NOME = {u: NOME[k] for k, u in ENT.items()}
    sys.stdout.write(json.dumps({
        "documentos": [
            {
                "id": d["doc"],
                "tipo_taxonomia": d["tipo"],
                "entidade": {"razao_social": UUID_NOME[d["ent"]]},
                "periodo": TIPO_PER[d["per"]],
                "documento_versao": [{"id": d["ver"], "nome_original": d["tipo"] + ".pdf"}],
            }
            for d in docs
        ],
        "campos": [
            {
                "id": f"{d['ver']}-{i}",
                "documento_versao_id": d["ver"],
                "chave": k, "valor_num": v, "secao": sec, "secao_canonica": ca,
                # `ordem` = posição da linha NO DOCUMENTO (db/migrations/0027). É o
                # que permite ao export desambiguar rótulo repetido em vez de
                # colapsar as duas linhas numa só.
                "ordem": i,
                "entidade_coluna": ecol, "periodo_coluna": pcol,
                "valor_texto": None, "unidade": u, "confianca": cf, "origem_pagina": 1,
                "status_aceite": "aceito", "aceito_por": "fixture",
                "aceito_em": "2026-07-27T00:00:00Z",
            }
            for d in docs
            for i, (k, v, sec, pcol, ecol, u, cf, ca) in enumerate(d["linhas"])
        ],
    }, ensure_ascii=False))
else:
    sys.stdout.write("\n".join(out) + "\n")
