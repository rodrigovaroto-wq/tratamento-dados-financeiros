# -*- coding: utf-8 -*-
"""Motor do book PIRAQUARA: monta os três balanços de cada exercício, resolve
as contas calculadas (dívida, mútuos, MEP, provisão para passivo a descoberto),
fecha o PL pela DRE e o caixa pelo balanço — e VALIDA tudo por `assert`.

A ordem de montagem é a ordem de dependência, e ela é o desenho:

  1. Contas declaradas + contas calculadas por contrato (empréstimos, mútuos).
  2. DRE das controladas, lida desse balanço parcial (depreciação, PECLD,
     provisões e impairment são variação de conta; juros são os do contrato).
  3. PL: 2023 fecha o balanço de abertura; 2024 e 2025 são o saldo anterior
     MAIS o resultado da DRE (não há distribuição nem aumento de capital).
  4. Disponível: 2023 declarado; 2024 e 2025 fecham Ativo = Passivo + PL.
  5. Holding por último: MEP = PL da controlada, e o que passar de zero para
     baixo vira provisão para passivo a descoberto.

Sem ruído determinístico (o canastra tem): os valores declarados já são
quebrados, e o caixa que fecha o balanço sai quebrado por construção. Sem
calibração por PL-alvo: o PL negativo é o que a DRE produz.
"""

import dados as D
import demonstracoes as X

SECOES = ["AC", "ANC", "PC", "PNC", "PL"]
LABEL_SECAO = {
    "AC": "ATIVO CIRCULANTE", "ANC": "ATIVO NÃO CIRCULANTE", "PC": "PASSIVO CIRCULANTE",
    "PNC": "PASSIVO NÃO CIRCULANTE", "PL": "PATRIMÔNIO LÍQUIDO",
}

soma = X.soma
soma_folhas = X.soma_secao
valor_conta = X.valor


def _resolve(marcador, ano, pl_sub):
    """Valor de uma conta calculada no exercício, ou None se ela não existe."""
    if marcador == D.EMPRESTIMOS_CP:
        v = X.saldos_emprestimos(ano)[0]
    elif marcador == D.EMPRESTIMOS_RECLASS:
        v = X.saldos_emprestimos(ano)[1]
    elif marcador == D.EMPRESTIMOS_LP:
        v = X.saldos_emprestimos(ano)[2]
    elif isinstance(marcador, tuple) and marcador[0] == D.MUTUO:
        v = X.saldo_mutuo(marcador[1], ano)
    elif isinstance(marcador, tuple) and marcador[0] == D.MEP:
        v = max(pl_sub[marcador[1]], 0)
    elif isinstance(marcador, tuple) and marcador[0] == D.PROVISAO_DESCOBERTO:
        v = max(-pl_sub[marcador[1]], 0)
    else:
        raise ValueError(f"marcador desconhecido: {marcador!r}")
    # Saldo zero de conta CALCULADA = a conta não existe no exercício (o
    # empréstimo de longo prazo em 2025, a provisão enquanto o PL é positivo, o
    # mútuo antes do contrato). Célula vazia no comparativo, nunca zero.
    #
    # EXCEÇÃO: a MEP. O investimento na Metalúrgica EXISTE em 2025 e vale zero
    # — a Nota 4 diz "mantido por valor zero" e a provisão para passivo a
    # descoberto (7.355) é a contrapartida. Em branco, a linha 2025 lia como
    # "a conta não existia" e o texto extraído saía "- MEP 11.006 10.641": um
    # leitor por linha punha 11.006 em 2025 (achado da revisão de 22/09/2026,
    # regra 1 pelo avesso — zero medido apresentado como ausência).
    if isinstance(marcador, tuple) and marcador[0] == D.MEP:
        return v
    return v or None


def balanco_parcial(ent, ano, pl_sub=None):
    """Plano projetado no exercício, com o Disponível e o PLUG ainda em aberto."""
    bp = {}
    for secao, subs in D.PLANOS[ent]().items():
        bp[secao] = {}
        for sub, contas in subs.items():
            if contas == D.PLUG:
                bp[secao][sub] = D.PLUG
                continue
            folhas = []
            for rotulo, v in contas:
                if v == D.CAIXA:
                    folhas.append((rotulo, D.CAIXA))
                    continue
                if isinstance(v, dict):
                    v = v.get(ano)
                else:
                    v = _resolve(v, ano, pl_sub)
                if v is not None:
                    folhas.append((rotulo, v))
            if folhas:
                bp[secao][sub] = folhas
    return bp


def _sem_marcadores(contas):
    return [(r, v) for r, v in contas if v != D.CAIXA]


def fechar(bp, ano, pl_anterior, resultado, ent):
    """Resolve PLUG e Disponível. Em 2023 o caixa é declarado e o acumulado
    fecha; depois, o acumulado é saldo anterior + resultado e o caixa fecha."""
    def s(secao):
        return sum(soma(_sem_marcadores(c)) for c in bp[secao].values() if c != D.PLUG)

    passivo = s("PC") + s("PNC")
    pl_outros = s("PL")
    if pl_anterior is None:
        caixa = D.CAIXA_2023[ent]
        pl = s("AC") + s("ANC") + caixa - passivo
    else:
        pl = pl_anterior + resultado
        caixa = passivo + pl - s("AC") - s("ANC")
        assert caixa > 0, f"{ent} {ano}: o caixa que fecha o balanço ficou {caixa} — revise o plano"
    for sub, contas in bp["AC"].items():
        bp["AC"][sub] = [(r, caixa if v == D.CAIXA else v) for r, v in contas]
    plug = pl - pl_outros
    for sub, contas in bp["PL"].items():
        if contas == D.PLUG:
            bp["PL"][sub] = [("Prejuízos acumulados" if plug < 0 else "Lucros acumulados", plug)]

    tot = {k: soma_folhas(bp[k]) for k in SECOES}
    tot["ATIVO"] = tot["AC"] + tot["ANC"]
    tot["PASSIVO_PL"] = tot["PC"] + tot["PNC"] + tot["PL"]
    tot["plug"] = plug
    tot["caixa"] = caixa
    assert tot["PL"] == pl
    assert tot["ATIVO"] == tot["PASSIVO_PL"], f"{ent} {ano}: balanço não fechou"
    return bp, tot


def construir():
    """Devolve (bp, tot, dre) — dre = {ent: {ano: linhas}}."""
    bp = {a: {} for a in D.ANOS}
    tot = {a: {} for a in D.ANOS}

    # 1–2. Balanço parcial das controladas e a DRE lida dele. A DRE só usa
    # contas que não dependem do caixa nem do PL, então pode vir antes deles.
    for ano in D.ANOS:
        for k in D.CONTROLADAS:
            bp[ano][k] = balanco_parcial(k, ano)
    dre = {"metalurgica": X.dre_metalurgica(bp), "servicos": X.dre_servicos(bp)}
    res = {k: {a: X.resultado(dre[k][a]) for a in D.ANOS} for k in D.CONTROLADAS}

    # 3–4. PL pela DRE, caixa pelo balanço.
    for k in D.CONTROLADAS:
        pl_ant = None
        for ano in D.ANOS:
            bp[ano][k], tot[ano][k] = fechar(bp[ano][k], ano, pl_ant, res[k][ano], k)
            pl_ant = tot[ano][k]["PL"]

    # 5. Holding.
    dre["holding"] = X.dre_holding(res["metalurgica"], res["servicos"])
    pl_ant = None
    for ano in D.ANOS:
        pl_sub = {k: tot[ano][k]["PL"] for k in D.CONTROLADAS}
        bp[ano]["holding"] = balanco_parcial("holding", ano, pl_sub)
        bp[ano]["holding"], tot[ano]["holding"] = fechar(
            bp[ano]["holding"], ano, pl_ant, X.resultado(dre["holding"][ano]), "holding")
        pl_ant = tot[ano]["holding"]["PL"]

    _rotulo_do_acumulado(bp, tot)
    validar(bp, tot, dre)
    return bp, tot, dre


def _rotulo_do_acumulado(bp, tot):
    """UM rótulo por entidade para a conta de resultados acumulados, nos três
    exercícios. Rotular pelo sinal de cada ano faz o comparativo abrir duas
    linhas ("Lucros acumulados" numa coluna, "Prejuízos acumulados" na outra)
    para o mesmo saldo — que nenhum balanço real imprime."""
    for k in D.ORDEM:
        sinais = {tot[a][k]["plug"] < 0 for a in D.ANOS}
        rot = ("Lucros (prejuízos) acumulados" if len(sinais) > 1
               else "Prejuízos acumulados" if sinais == {True} else "Lucros acumulados")
        for a in D.ANOS:
            bp[a][k]["PL"]["Lucros ou Prejuízos Acumulados"] = [(rot, tot[a][k]["plug"])]


def validar(bp, tot, dre):
    """As amarrações que o book promete. Cada uma é uma frase do README."""
    for ano in D.ANOS:
        ant = X._anterior(ano)
        for k in D.ORDEM:
            t = tot[ano][k]
            assert t["ATIVO"] == t["PASSIVO_PL"]
            # DRE → lucro → PL (2023 não tem PL de abertura no book).
            if ant is not None:
                assert X.resultado(dre[k][ano]) == t["PL"] - tot[ant][k]["PL"], (k, ano)

        # Mútuos: as duas pernas de cada contrato, ao real.
        m, s, h = bp[ano]["metalurgica"], bp[ano]["servicos"], bp[ano]["holding"]
        assert (valor_conta(m, "PNC", "Partes Relacionadas", "Mútuo a pagar - Piraquara Participações")
                == valor_conta(h, "ANC", "Créditos com Partes Relacionadas", "Mútuo a receber"))
        assert (valor_conta(m, "PNC", "Partes Relacionadas", "Mútuo a pagar - Piraquara Montagens")
                == valor_conta(s, "ANC", "Créditos com Partes Relacionadas", "Mútuo a receber"))
        # Juros de mútuo: despesa numa DRE = receita na outra.
        desp = -[v for r, v, _ in dre["metalurgica"][ano] if r.startswith("(-) Juros sobre mútuos")][0]
        rec = ([v for r, v, _ in dre["holding"][ano] if r.startswith("Receita de juros")][0]
               + [v for r, v, _ in dre["servicos"][ano] if r.startswith("Receitas financeiras")][0])
        assert desp == rec, (ano, desp, rec)
        # MEP líquido (investimento − provisão) = PL da controlada.
        for k in D.CONTROLADAS:
            inv = valor_conta(h, "ANC", "Investimentos", f"Participação em {D.ENTIDADES[k]['curto']}")
            prov = valor_conta(h, "PNC", "Provisões", "Provisão para passivo a descoberto") \
                if k == "metalurgica" else 0
            assert inv - prov == tot[ano][k]["PL"], (k, ano)
        # Dívida: contratos = contas de empréstimo do balanço.
        emp = soma(m["PC"].get("Empréstimos e Financiamentos", [])) + \
            soma(m["PNC"].get("Empréstimos e Financiamentos", []))
        assert emp == X.divida_bancaria(ano)

    # A história que o book existe para contar — se o plano for mexido e ela
    # deixar de valer, a geração para aqui, e não num teste lá na frente.
    assert tot[2025]["metalurgica"]["PL"] < 0, "a Metalúrgica tem de fechar 2025 com PL negativo"
    assert tot[2024]["metalurgica"]["PL"] > 0 and tot[2023]["metalurgica"]["PL"] > 0
    assert tot[2025]["holding"]["PL"] > 0
    cov = X.covenant(bp, dre["metalurgica"])
    assert not cov[2023]["rompido"] and not cov[2024]["rompido"], cov
    assert cov[2025]["rompido"] and cov[2025]["ebitda"] > 0, cov[2025]
    assert "PNC" not in bp[2025]["metalurgica"] or \
        "Empréstimos e Financiamentos" not in bp[2025]["metalurgica"]["PNC"]
    for ano in D.ANOS[1:]:
        X.dfc_metalurgica(bp, dre["metalurgica"], ano)   # assert interno: fecha no caixa
    X.extrato(bp, 2025)                                   # assert interno: termina no caixa


if __name__ == "__main__":
    bp, tot, dre = construir()
    print(f"{D.GRUPO} — validação das amarrações (R$ mil)")
    for ano in D.ANOS:
        print(f"\n--- {ano} ---")
        for k in D.ORDEM:
            t = tot[ano][k]
            print(f"  {k:12s} Ativo {t['ATIVO']:>8,} | Passivo {t['PC'] + t['PNC']:>8,} | "
                  f"PL {t['PL']:>8,} | caixa {t['caixa']:>7,} | resultado "
                  f"{X.resultado(dre[k][ano]):>8,}")
    cov = X.covenant(bp, dre["metalurgica"])
    for ano in D.ANOS:
        print(ano, cov[ano])
    print("\nTodas as amarrações fecharam.")
