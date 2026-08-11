# -*- coding: utf-8 -*-
"""Motor do book CANASTRA: monta o balanço de cada exercício a partir das
contas-folha, calcula os subtotais, resolve o MEP da holding, apura as
eliminações do combinado e VALIDA tudo por `assert`.

Duas diferenças de projeto em relação ao motor do `book-vertentes`, e as duas
são deliberadas:

1. **Não há calibração por PL-alvo.** Lá o passivo inteiro era multiplicado por
   um fator até o PL cair num alvo escolhido. Isso preserva a composição dentro
   de um ano, mas com TRÊS exercícios o fator vira uma distorção entre anos: uma
   conta que cresce no plano de contas pode DECRESCER no balanço só porque o
   fator daquele ano é menor. O histórico é o insumo do modelo — se ele mentir
   sobre a direção, o teste inteiro mente. Aqui o PL é o que a composição
   produz, e quem absorve é a conta de resultados acumulados, que é o que
   acontece de verdade numa empresa que vem acumulando perda.

2. **O número quebrado vem de RUÍDO determinístico, não do fator.** Demonstração
   real não tem valor redondo, e valor redondo demais deixa o teste fácil (soma
   de redondos fecha na cabeça). O ruído é uma função do rótulo da conta, então é
   reprodutível: rodar duas vezes dá o mesmo book, e o gabarito continua valendo.
"""

import hashlib

import dados as D

SECOES = ["AC", "ANC", "PC", "PNC", "PL"]
LABEL_SECAO = {
    "AC": "ATIVO CIRCULANTE",
    "ANC": "ATIVO NÃO CIRCULANTE",
    "PC": "PASSIVO CIRCULANTE",
    "PNC": "PASSIVO NÃO CIRCULANTE",
    "PL": "PATRIMÔNIO LÍQUIDO",
}

# Amplitude do ruído: ±0,7% do valor da conta. Grande o bastante para que
# nenhum total feche "redondo", pequeno o bastante para não mexer na história
# (uma conta de 20.000 varia até 140).
RUIDO = 0.007


def _ruido(rotulo, valor):
    """Perturbação determinística pelo RÓTULO da conta. Duas propriedades que a
    escolha do que entra no hash garante, e as duas importam:

    • **Reprodutível** — roda duas vezes, dá o mesmo book; o gabarito continua
      valendo em qualquer máquina.
    • **Constante entre exercícios** — o fator é o mesmo nos três anos, então
      conta que não se mexe (terreno, capital social) continua com o MESMO saldo
      nos três, e conta que cresce continua crescendo. Sortear por (conta, ano)
      faria o terreno oscilar de ano para ano, o que é uma movimentação que o
      documento não explica — e um teste que afirma o que a realidade não faz é
      pior que um teste redondo demais."""
    if valor == 0:
        return 0
    h = hashlib.sha256(rotulo.encode("utf-8")).digest()
    # [-1, 1) a partir de dois bytes do hash.
    fracao = (int.from_bytes(h[:2], "big") / 32768.0) - 1.0
    return int(round(valor * (1 + RUIDO * fracao)))


def soma_folhas(secao_dict):
    """Soma as contas-folha de uma seção (ignora o marcador PLUG)."""
    t = 0
    for contas in secao_dict.values():
        if contas == "PLUG":
            continue
        t += sum(v for _, v in contas)
    return t


def balanco_do_ano(plano, ano, com_ruido=True):
    """Projeta o plano plurianual no exercício `ano`.

    Conta sem valor no ano NÃO ENTRA — e essa é a regra que importa: no
    comparativo, a coluna do exercício em que a conta não existia fica vazia, e
    preencher zero ali seria afirmar que o saldo era zero, que é outra coisa."""
    bp = {}
    for secao, subs in plano.items():
        bp[secao] = {}
        for sub, contas in subs.items():
            if contas == "PLUG":
                bp[secao][sub] = "PLUG"
                continue
            folhas = []
            for rotulo, por_ano in contas:
                if ano not in por_ano:
                    continue
                v = por_ano[ano]
                rot = D.rotulo_do_ano(rotulo, ano)
                aplica = com_ruido and not rot.startswith(D.SEM_RUIDO)
                folhas.append((rot, _ruido(rot, v) if aplica else v))
            if folhas:
                bp[secao][sub] = folhas
        # Subseção que ficou sem nenhuma conta no ano não aparece no documento.
        bp[secao] = {k: v for k, v in bp[secao].items() if v}
    return bp


def fechar_entidade(bp):
    """Calcula subtotais e resolve o PLUG (resultados acumulados) para que
    Ativo = Passivo + PL. Devolve (bp, totais)."""
    ativo = soma_folhas(bp["AC"]) + soma_folhas(bp["ANC"])
    passivo = soma_folhas(bp["PC"]) + soma_folhas(bp["PNC"])
    pl_outros = soma_folhas(bp["PL"])
    pl_total = ativo - passivo
    plug = pl_total - pl_outros

    for sub, contas in bp["PL"].items():
        if contas == "PLUG":
            rotulo = "Prejuízos acumulados" if plug < 0 else "Lucros acumulados"
            bp["PL"][sub] = [(rotulo, plug)]

    totais = {
        "AC": soma_folhas(bp["AC"]),
        "ANC": soma_folhas(bp["ANC"]),
        "ATIVO": ativo,
        "PC": soma_folhas(bp["PC"]),
        "PNC": soma_folhas(bp["PNC"]),
        "PL": pl_total,
        "PASSIVO_PL": passivo + pl_total,
        "plug": plug,
    }
    assert totais["ATIVO"] == totais["PASSIVO_PL"], "balanço não fechou"
    return bp, totais


def valor_conta(bp, secao, sub, prefixo):
    """Lê o valor JÁ construído de uma conta pelo início do rótulo. É por aqui
    que os documentos anexos (mapa de dívida, mútuos, aging) se amarram ao
    balanço: nenhum deles digita o próprio total."""
    for rot, v in bp[secao].get(sub, []):
        if rot.startswith(prefixo):
            return v
    return 0


def soma_prefixos(bp, secao, pares):
    return sum(valor_conta(bp, secao, sub, pref) for sub, pref in pares)


def construir():
    """Monta os três exercícios de todas as entidades. Devolve (bp, tot)."""
    bp = {a: {} for a in D.ANOS}
    tot = {a: {} for a in D.ANOS}

    for ano in D.ANOS:
        for k in D.CONTROLADAS:
            bp[ano][k] = balanco_do_ano(D.PLANOS[k](), ano)
            bp[ano][k], tot[ano][k] = fechar_entidade(bp[ano][k])

    # A holding só pode ser montada DEPOIS das controladas: o ativo dela é o PL
    # delas (MEP), e o mútuo a receber é o espelho do que elas declaram dever.
    for ano in D.ANOS:
        mep_pos, provisao = [], 0
        for k in D.CONTROLADAS:
            parcela = int(round(D.PARTICIPACAO[k] * tot[ano][k]["PL"]))
            nome = D.ENTIDADES[k]["razao_social"]
            pct = int(round(D.PARTICIPACAO[k] * 100))
            if parcela > 0:
                mep_pos.append((f"Participação em {nome} ({pct}%) - MEP", parcela))
            else:
                # Investimento em controlada com PL negativo fica em zero, e o
                # excedente vira provisão para passivo a descoberto no passivo.
                provisao += -parcela
        mutuos = sum(
            valor_conta(bp[ano][k], "PC", "Partes Relacionadas", "Mútuos a pagar")
            for k in D.CONTROLADAS
        )
        bp[ano]["holding"] = D.plano_holding(ano, mep_pos, provisao, mutuos)
        bp[ano]["holding"] = balanco_do_ano_holding(bp[ano]["holding"], ano)
        bp[ano]["holding"], tot[ano]["holding"] = fechar_entidade(bp[ano]["holding"])
        tot[ano]["_mep_total"] = sum(v for _, v in mep_pos)
        tot[ano]["_provisao_desc"] = provisao
        tot[ano]["_mutuos_holding"] = mutuos

    return bp, tot


def balanco_do_ano_holding(plano, ano):
    """A holding já vem com valores por ano fechados (o motor os calculou), então
    aqui é só desembrulhar o dict {ano: valor} — SEM ruído: os valores dela são
    espelho de números que já existem em outra entidade, e ruído aqui quebraria
    a eliminação do combinado."""
    bp = {}
    for secao, subs in plano.items():
        bp[secao] = {}
        for sub, contas in subs.items():
            if contas == "PLUG":
                bp[secao][sub] = "PLUG"
                continue
            folhas = [(rot, por_ano[ano]) for rot, por_ano in contas if ano in por_ano]
            if folhas:
                bp[secao][sub] = folhas
        bp[secao] = {k: v for k, v in bp[secao].items() if v}
    return bp


# ---------------------------------------------------------------- COMBINADO --
def eliminacoes(bp, tot, ano):
    """As contrapartes intragrupo, lidas dos DOIS lados (é o que faz a
    eliminação fechar sem número digitado)."""
    mutuos = tot[ano]["_mutuos_holding"]
    cc = valor_conta(bp[ano]["transportes"], "AC", "Contas a Receber", "Conta corrente a receber")
    alug = valor_conta(bp[ano]["imob"], "AC", "Contas a Receber", "Aluguéis a receber - Canastra Indústria")
    forn_agro = valor_conta(bp[ano]["agro"], "AC", "Contas a Receber", "Contas a receber intragrupo")
    forn_ind = valor_conta(bp[ano]["comercial"], "PC", "Fornecedores", "Fornecedores intragrupo")
    return [
        ("Mútuos holding × controladas", mutuos),
        ("Conta corrente CN Transportes × Canastra Indústria", cc),
        ("Aluguéis Canastra SPE × Canastra Indústria", alug),
        ("Fornecimento Canastra Agroflorestal × Canastra Indústria", forn_agro),
        ("Fornecimento Canastra Indústria × Canastra Comercial", forn_ind),
    ]


def combinado(bp, tot, ano):
    ordem = D.ORDEM
    elim = eliminacoes(bp, tot, ano)
    elim_mutuos = sum(v for _, v in elim)
    elim_invest = tot[ano]["_mep_total"]
    elim_provisao = tot[ano]["_provisao_desc"]
    # Participação de não controladores: 35% da CN Transportes.
    nci = int(round((1 - D.PARTICIPACAO["transportes"]) * tot[ano]["transportes"]["PL"]))

    soma = {s: sum(tot[ano][e][s] for e in ordem)
            for s in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL")}
    ativo_comb = soma["ATIVO"] - elim_invest - elim_mutuos
    passivo_comb = soma["PC"] + soma["PNC"] - elim_provisao - elim_mutuos
    pl_comb = tot[ano]["holding"]["PL"] + nci

    assert ativo_comb == passivo_comb + pl_comb, (
        f"combinado {ano} não fechou: ativo={ativo_comb} passivo+pl={passivo_comb + pl_comb}")

    return {"ordem": ordem, "soma": soma, "elim": elim, "elim_invest": elim_invest,
            "elim_mutuos": elim_mutuos, "elim_provisao": elim_provisao, "nci": nci,
            "ativo": ativo_comb, "passivo": passivo_comb, "pl": pl_comb,
            "pl_holding": tot[ano]["holding"]["PL"]}


if __name__ == "__main__":
    bp, tot = construir()
    print("=" * 104)
    print(f"{D.GRUPO} — validação das amarrações (R$ mil)")
    print("=" * 104)
    for ano in D.ANOS:
        print(f"\n--- {ano} ---")
        for k in D.ORDEM:
            t = tot[ano][k]
            lc = (t["AC"] / t["PC"]) if t["PC"] else 0
            print(f"  {k:12s} Ativo {t['ATIVO']:>10,} | Passivo {t['PC'] + t['PNC']:>10,} | "
                  f"PL {t['PL']:>9,} | result.acum {t['plug']:>10,} | LC {lc:>5.2f} | "
                  f"CCL {t['AC'] - t['PC']:>9,}")
        c = combinado(bp, tot, ano)
        print(f"  COMBINADO    Ativo {c['ativo']:>10,} | Passivo {c['passivo']:>10,} | "
              f"PL {c['pl']:>9,} (holding {c['pl_holding']:,} + não control. {c['nci']:,})")
        print(f"     elim: investimentos {c['elim_invest']:,} | passivo a descoberto "
              f"{c['elim_provisao']:,} | intragrupo {c['elim_mutuos']:,}")
    print("\nTodas as amarrações fecharam.")
