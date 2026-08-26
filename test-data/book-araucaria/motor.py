# -*- coding: utf-8 -*-
"""Motor do book ARAUCÁRIA: monta o balanço de cada exercício a partir das
contas-folha, calcula os subtotais, resolve o MEP da holding, apura as
eliminações do combinado e VALIDA tudo por `assert`.

Duas diferenças de projeto em relação ao motor do `book-canastra`, e as duas
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
    """Monta os quatro exercícios de todas as entidades. Devolve (bp, tot).

    A diferença para o motor do `book-canastra`: uma entidade só é montada nos
    exercícios em que ela EXISTE. Empresa incorporada no meio do histórico não
    vira uma coluna de zeros — ela some da tabela, que é o que o documento faz.
    Zerar seria afirmar que a empresa existia e não tinha nada, e é justamente
    essa afirmação que faz alguém somar o mesmo estoque duas vezes."""
    bp = {a: {} for a in D.ANOS}
    tot = {a: {} for a in D.ANOS}

    for ano in D.ANOS:
        for k in D.CONTROLADAS:
            if not D.existe_em(k, ano):
                continue
            bp[ano][k] = balanco_do_ano(D.PLANOS[k](), ano)
            bp[ano][k], tot[ano][k] = fechar_entidade(bp[ano][k])

    # A holding só pode ser montada DEPOIS das controladas: o ativo dela é o PL
    # delas (MEP), e o mútuo a receber é o espelho do que elas declaram dever.
    for ano in D.ANOS:
        mep_pos, provisao = [], 0
        for k in vivas(ano):
            parcela = int(round(D.PARTICIPACAO[k] * tot[ano][k]["PL"]))
            nome = D.ENTIDADES[k]["razao_social"]
            pct = int(round(D.PARTICIPACAO[k] * 100))
            if parcela > 0:
                mep_pos.append((f"Participação em {nome} ({pct}%) - MEP", parcela))
            else:
                # Investimento em controlada com PL negativo fica em zero, e o
                # excedente vira provisão para passivo a descoberto no passivo.
                provisao += -parcela
        mutuos = sum(mutuo_a_pagar(bp[ano][k]) for k in vivas(ano))
        bp[ano]["holding"] = D.plano_holding(ano, mep_pos, provisao, mutuos)
        bp[ano]["holding"] = balanco_do_ano_holding(bp[ano]["holding"], ano)
        bp[ano]["holding"], tot[ano]["holding"] = fechar_entidade(bp[ano]["holding"])
        tot[ano]["_mep_total"] = sum(v for _, v in mep_pos)
        tot[ano]["_provisao_desc"] = provisao
        tot[ano]["_mutuos_holding"] = mutuos

    return bp, tot


def vivas(ano):
    """As controladas que EXISTEM neste exercício, na ordem do combinado."""
    return [k for k in D.CONTROLADAS if D.existe_em(k, ano)]


def ordem_do_ano(ano):
    return ["holding"] + vivas(ano)


def mutuo_a_pagar(bp_ent):
    """O mútuo com a controladora, onde quer que a empresa o tenha classificado.

    Não é rigor de estilo: neste book uma parte das empresas classifica o mútuo
    no circulante e outra no não circulante, porque o vencimento é indeterminado
    e cada contador decidiu diferente. Procurar em um lugar só devolveria ZERO
    para metade do grupo — e zero silencioso aqui desmonta a eliminação sem
    quebrar nenhum assert, porque o combinado fecharia igual, só inflado dos
    dois lados."""
    return sum(valor_conta(bp_ent, secao, "Partes Relacionadas", "Mútuos a pagar")
               for secao in ("PC", "PNC"))


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
    """As contrapartes intragrupo, lidas dos DOIS lados — e agora a partir da
    TABELA `D.INTRAGRUPO`, não de uma função escrita par a par.

    Por que a tabela importa mais aqui do que no `book-canastra`: com 11 pares,
    esquecer um não quebra nada visível. O combinado continua fechando, porque o
    ativo e o passivo ficam inflados na MESMA medida — some do lado do crédito e
    do lado do débito ao mesmo tempo. O `assert` passa, o documento sai, e o
    total do grupo está errado para mais. É o modo de falha preferido deste
    repositório: aquele que não deixa rastro.

    O par cujo credor não existe no exercício simplesmente não entra: a
    Ferragens foi incorporada em 2024, e cobrar dela um saldo em 2025 seria
    inventar contraparte."""
    linhas = []
    for rotulo, credor, secao, sub, prefixo in D.INTRAGRUPO:
        if not D.existe_em(credor, ano):
            continue
        v = valor_conta(bp[ano][credor], secao, sub, prefixo)
        if v:
            linhas.append((rotulo, v))
    linhas.append(("Mútuos holding × controladas", tot[ano]["_mutuos_holding"]))
    return linhas


def nao_controladores(tot, ano):
    """Participação de não controladores, somada sobre TODAS as minoritárias.

    Duas neste book (AR Transportes 30%, Araucária Varejo 45%) exatamente para
    que o número não possa sair certo por acidente: com uma origem só, trocar a
    base ou o sinal ainda pode acertar; com duas de tamanhos diferentes, não."""
    total = 0
    for k in vivas(ano):
        fatia = 1 - D.PARTICIPACAO[k]
        if fatia > 0:
            total += int(round(fatia * tot[ano][k]["PL"]))
    return total


def combinado(bp, tot, ano):
    ordem = ordem_do_ano(ano)
    elim = eliminacoes(bp, tot, ano)
    elim_mutuos = sum(v for _, v in elim)
    elim_invest = tot[ano]["_mep_total"]
    elim_provisao = tot[ano]["_provisao_desc"]
    nci = nao_controladores(tot, ano)

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
        for k in ordem_do_ano(ano):
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
