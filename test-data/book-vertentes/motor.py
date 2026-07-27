# -*- coding: utf-8 -*-
"""Motor: calcula subtotais, o MEP da holding, as eliminações do combinado e
VALIDA todas as amarrações. Nenhum total é digitado à mão."""

import dados as D

SECOES = ["AC", "ANC", "PC", "PNC", "PL"]
LABEL_SECAO = {
    "AC": "ATIVO CIRCULANTE",
    "ANC": "ATIVO NÃO CIRCULANTE",
    "PC": "PASSIVO CIRCULANTE",
    "PNC": "PASSIVO NÃO CIRCULANTE",
    "PL": "PATRIMÔNIO LÍQUIDO",
}

# Contrapartes intragrupo (para as eliminações do combinado).
# 2025 e 2024: (descrição, valor2025, valor2024)
INTERCOMPANY = [
    ("Mútuos holding × controladas", 22400, 10600),
    ("Conta corrente Metalúrgica × VT Logística", 1400, 1568),
    ("Aluguéis SPE × Metalúrgica", 640, 520),
]


def soma_folhas(secao_dict):
    """Soma todas as contas-folha de uma seção (ignora o marcador PLUG)."""
    t = 0
    for contas in secao_dict.values():
        if contas == "PLUG":
            continue
        t += sum(v for _, v in contas)
    return t


def escalar_passivo(bp, pl_alvo):
    """Calibra a MAGNITUDE do passivo para que o PL caia no alvo, preservando a
    COMPOSIÇÃO curada (é a composição que conta a história de distress: dívida
    concentrada no curto prazo, fornecedor em atraso, parcelamento tributário).
    Efeito colateral desejável: os valores deixam de ser todos redondos —
    demonstração real é cheia de número quebrado."""
    ativo = soma_folhas(bp["AC"]) + soma_folhas(bp["ANC"])
    passivo_atual = soma_folhas(bp["PC"]) + soma_folhas(bp["PNC"])
    passivo_alvo = ativo - pl_alvo
    if passivo_atual <= 0 or passivo_alvo <= 0:
        return bp
    f = passivo_alvo / passivo_atual
    for secao in ("PC", "PNC"):
        for sub, contas in bp[secao].items():
            bp[secao][sub] = [(rot, int(round(v * f))) for rot, v in contas]
    return bp


def fechar_entidade(bp):
    """Calcula subtotais e resolve o PLUG (Resultados Acumulados) para que
    Ativo = Passivo + PL. Devolve (bp_resolvido, totais)."""
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


# PL-alvo por entidade e ano (a história do grupo, em R$ mil):
# a Metalúrgica queima o PL entre 2024 e 2025 mas ainda fica positiva e fina;
# a Componentes entra em PASSIVO A DESCOBERTO; a SPE segura o patrimônio do
# grupo (imóveis); a Logística fica quase no zero.
PL_ALVO = {
    2024: {"metalurgica": 24800, "componentes": -3200, "logistica": 1450, "spe": 15900},
    2025: {"metalurgica": 6900, "componentes": -12400, "logistica": 260, "spe": 16500},
}


def valor_conta(bp, secao, sub, prefixo):
    """Lê o valor (já escalado) de uma conta pelo início do rótulo."""
    for rot, v in bp[secao].get(sub, []):
        if rot.startswith(prefixo):
            return v
    return 0


def construir():
    bp = {2025: {}, 2024: {}}
    tot = {2025: {}, 2024: {}}

    bp[2025]["metalurgica"] = D.bp_metalurgica()[2025]
    bp[2024]["metalurgica"] = D.bp_metalurgica_2024()
    # contrapartes intragrupo que faltavam na Metalúrgica (o combinado precisa
    # dos dois lados para as eliminações fecharem)
    bp[2025]["metalurgica"]["AC"]["Outros Créditos"].append(
        ("Conta corrente a receber - VT Logística e Transportes", 1400))
    bp[2024]["metalurgica"]["AC"]["Outros Créditos"].append(
        ("Conta corrente a receber - VT Logística e Transportes", 1568))
    bp[2025]["metalurgica"]["PC"]["Outras Obrigações"].append(
        ("Aluguéis a pagar - Vertentes Imóveis SPE", 640))
    bp[2024]["metalurgica"]["PC"]["Outras Obrigações"].append(
        ("Aluguéis a pagar - Vertentes Imóveis SPE", 520))

    for ano in (2025, 2024):
        bp[ano]["componentes"] = D.bp_componentes(ano)
        bp[ano]["logistica"] = D.bp_logistica(ano)
        bp[ano]["spe"] = D.bp_spe(ano)

    # 1) calibra o passivo de cada controlada para o PL-alvo e fecha
    for ano in (2025, 2024):
        for k in ("metalurgica", "componentes", "logistica", "spe"):
            bp[ano][k] = escalar_passivo(bp[ano][k], PL_ALVO[ano][k])
            bp[ano][k], tot[ano][k] = fechar_entidade(bp[ano][k])

    # 2) holding: MEP capado em zero + provisão de passivo a descoberto, e os
    #    mútuos a receber lidos dos valores REAIS (já escalados) das controladas
    for ano in (2025, 2024):
        mep_pos, provisao = [], 0
        for k in ("metalurgica", "componentes", "logistica", "spe"):
            parcela = int(round(D.PARTICIPACAO[k] * tot[ano][k]["PL"]))
            nome = D.ENTIDADES[k]["razao_social"]
            pct = int(D.PARTICIPACAO[k] * 100)
            if parcela > 0:
                mep_pos.append((f"Participação em {nome} ({pct}%) - MEP", parcela))
            else:
                provisao += -parcela
        mutuos = (valor_conta(bp[ano]["metalurgica"], "PC", "Partes Relacionadas", "Mútuos a pagar")
                  + valor_conta(bp[ano]["componentes"], "PC", "Partes Relacionadas", "Mútuos a pagar"))
        bp[ano]["holding"] = D.bp_holding(ano, mep_pos, provisao, mutuos)
        bp[ano]["holding"], tot[ano]["holding"] = fechar_entidade(bp[ano]["holding"])
        tot[ano]["_mep_total"] = sum(v for _, v in mep_pos)
        tot[ano]["_provisao_desc"] = provisao
        tot[ano]["_mutuos_holding"] = mutuos

    return bp, tot


def eliminacoes(bp, tot, ano):
    """Valores REAIS das contrapartes intragrupo (lidos das entidades já
    calibradas), para as eliminações do combinado."""
    m = tot[ano]["_mutuos_holding"]
    cc = valor_conta(bp[ano]["logistica"], "PC", "Partes Relacionadas", "Conta corrente")
    alug = valor_conta(bp[ano]["metalurgica"], "PC", "Outras Obrigações", "Aluguéis a pagar")
    return [
        ("Mútuos holding × controladas", m),
        ("Conta corrente Metalúrgica × VT Logística", cc),
        ("Aluguéis SPE × Metalúrgica", alug),
    ]


def combinado(bp, tot, ano):
    ordem = ["holding", "metalurgica", "componentes", "logistica", "spe"]
    elim = eliminacoes(bp, tot, ano)
    elim_mutuos = sum(v for _, v in elim)
    elim_invest = tot[ano]["_mep_total"]
    elim_provisao = tot[ano]["_provisao_desc"]
    nci = int(round(0.30 * tot[ano]["logistica"]["PL"]))

    soma = {s: sum(tot[ano][e][s] for e in ordem) for s in ("AC", "ANC", "ATIVO", "PC", "PNC", "PL")}
    ativo_comb = soma["ATIVO"] - elim_invest - elim_mutuos
    passivo_comb = soma["PC"] + soma["PNC"] - elim_provisao - elim_mutuos
    pl_comb = tot[ano]["holding"]["PL"] + nci

    assert ativo_comb == passivo_comb + pl_comb, (
        f"combinado {ano} nao fechou: ativo={ativo_comb} passivo+pl={passivo_comb+pl_comb}")

    return {"ordem": ordem, "soma": soma, "elim": elim, "elim_invest": elim_invest,
            "elim_mutuos": elim_mutuos, "elim_provisao": elim_provisao, "nci": nci,
            "ativo": ativo_comb, "passivo": passivo_comb, "pl": pl_comb,
            "pl_holding": tot[ano]["holding"]["PL"]}


if __name__ == "__main__":
    bp, tot = construir()
    print("=" * 92)
    print(f"{D.GRUPO} — validacao das amarracoes (R$ mil)")
    print("=" * 92)
    for ano in (2024, 2025):
        print(f"\n--- {ano} ---")
        for k in ("holding", "metalurgica", "componentes", "logistica", "spe"):
            t = tot[ano][k]
            lc = (t["AC"] / t["PC"]) if t["PC"] else 0
            print(f"  {k:12s} Ativo {t['ATIVO']:>9,} | Passivo {t['PC']+t['PNC']:>9,} | PL {t['PL']:>8,} | "
                  f"result.acum {t['plug']:>9,} | LC {lc:>4.2f} | CCL {t['AC']-t['PC']:>8,}")
        c = combinado(bp, tot, ano)
        print(f"  COMBINADO    Ativo {c['ativo']:>9,} | Passivo {c['passivo']:>9,} | PL {c['pl']:>8,} "
              f"(holding {c['pl_holding']:,} + nao control. {c['nci']:,})")
        print(f"     elim: investimentos {c['elim_invest']:,} | provisao passivo a descoberto {c['elim_provisao']:,} | intragrupo {c['elim_mutuos']:,}")
    print("\nTodas as amarracoes fecharam.")
