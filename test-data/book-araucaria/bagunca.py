# -*- coding: utf-8 -*-
"""A BAGUNÇA DELIBERADA do book ARAUCÁRIA — catalogada, com resposta certa.

Este arquivo existe para que a desordem do book seja um OBJETO, e não um efeito
colateral espalhado pelo gerador. A razão é a mesma que fez o `GABARITO.json`
existir nos dois books anteriores:

    CONFLITO SEM RESPOSTA CERTA NÃO É TESTE, É RUÍDO — E RUÍDO NÃO MEDE NADA,
    PORQUE QUALQUER SAÍDA PASSA.

Cada entrada de `ARMADILHAS` declara quatro coisas, e as quatro são cobradas
pelo `GUIA_DE_TESTE.md` gerado:

  • `chave`     — o identificador, para o resultado da rodada poder ser somado;
  • `o_que`     — o que a pessoa VÊ ao abrir os documentos;
  • `porque`    — por que isso acontece de verdade num kit de cliente;
  • `resposta`  — o que o sistema TEM de fazer. Sem esta linha a armadilha é
                  decoração.

A regra que separa este book de um gerador de lixo: **nada aqui inventa
inconsistência contábil.** Todo balanço fecha, o combinado fecha nos quatro
exercícios e nenhum anexo digita o próprio total. O que é confuso é a LEITURA —
nomes, versões, escalas, recortes e vigências —, não a aritmética.
"""

import dados as D
import motor as M


# ---------------------------------------------------------------------------
# A ELIMINAÇÃO INCOMPLETA — a versão preliminar do combinado.
#
# Esta é a armadilha mais cara do book, e a que motivou o `INTRAGRUPO`
# declarativo do `dados.py`. O controller do grupo fechou o combinado
# reconhecendo SÓ os pares intragrupo óbvios (mútuos e conta corrente); os
# outros seis o auditor achou depois. A versão preliminar circulou, foi para o
# banco e está no kit ao lado da definitiva.
#
# O que faz dela uma armadilha de verdade: a versão preliminar FECHA. Ativo e
# passivo caem na mesma medida quando um par deixa de ser eliminado, então o
# `assert` passa, o documento sai bonito e o ativo do grupo está inflado em
# dezenas de milhões. Um sistema que só confere "Ativo = Passivo + PL" dá as
# duas por boas.
# ---------------------------------------------------------------------------
PARES_RECONHECIDOS_NA_PRELIMINAR = {
    "Conta corrente AR Transportes × Araucária Serraria",
    "Mútuos holding × controladas",
}


def combinado_preliminar(bp, tot, ano):
    """O combinado como o controller o fechou, antes da revisão do auditor.

    Devolve a MESMA estrutura de `M.combinado`, com as eliminações reduzidas aos
    pares que ele reconheceu. Continua fechando — é justamente esse o ponto."""
    c = dict(M.combinado(bp, tot, ano))
    elim = [(r, v) for r, v in c["elim"] if r in PARES_RECONHECIDOS_NA_PRELIMINAR]
    elim_mutuos = sum(v for _, v in elim)
    ativo = c["soma"]["ATIVO"] - c["elim_invest"] - elim_mutuos
    passivo = c["soma"]["PC"] + c["soma"]["PNC"] - c["elim_provisao"] - elim_mutuos
    assert ativo == passivo + c["pl"], (
        "o combinado preliminar TEM de fechar — se ele não fechasse, a armadilha "
        "seria trivial e qualquer conferência de fechamento a pegaria")
    c.update(elim=elim, elim_mutuos=elim_mutuos, ativo=ativo, passivo=passivo)
    return c


def diferenca_preliminar(bp, tot, ano):
    """De quanto a versão preliminar infla o ativo combinado. É o número que a
    rodada tem de reencontrar."""
    return M.combinado(bp, tot, ano)["ativo"] - combinado_preliminar(bp, tot, ano)["ativo"]


# ---------------------------------------------------------------------------
# O CATÁLOGO.
# ---------------------------------------------------------------------------
ARMADILHAS = [
    dict(
        chave="combinado_preliminar",
        o_que="Dois combinados do MESMO exercício, com ativos diferentes, e os dois fecham "
              "(Ativo = Passivo + PL). A diferença chega a nove dígitos.",
        porque="O controller fechou reconhecendo só os pares intragrupo óbvios; o auditor achou "
               "os outros seis depois. A versão preliminar circulou e foi para o banco.",
        resposta="Vale a versão DEFINITIVA (sem a marca «CÓPIA NÃO AUDITADA» e com o quadro de "
                 "eliminações completo). O sistema tem de acusar a divergência entre as duas em "
                 "vez de escolher em silêncio — e conferir «Ativo = Passivo + PL» NÃO basta para "
                 "distingui-las, porque as duas fecham.",
    ),
    dict(
        chave="empresa_incorporada",
        o_que="A Araucária Ferragens tem balanço em 2022 e 2023 e DESAPARECE a partir de 2024. "
              "Duas contas da Serraria dão um salto em 2024 que a operação não explica: o estoque "
              "de madeira serrada sobe 73% num ano em que a receita caiu.",
        porque="Incorporação em 30/06/2024. O saldo da incorporada passa a estar DENTRO da "
               "incorporadora — é a mesma mercadoria, com outro CNPJ.",
        resposta="Somar as 14 empresas em 2023 e as 13 em 2025 está certo; somar «todas as "
                 "empresas de todos os anos» conta o mesmo estoque duas vezes. O salto de 2024 "
                 "NÃO é pendência de extração, e a nota explicativa é quem o explica.",
    ),
    dict(
        chave="receita_que_migrou",
        o_que="A receita da Araucária Comercial cai 62% de 2023 para 2024 sem que nada tenha "
              "piorado, e uma empresa nova (Araucária Trading) aparece com quase o mesmo valor.",
        porque="A operação de exportação migrou de uma empresa para a outra em 02/2024.",
        resposta="A queda é REAL no documento e FALSA como sinal de deterioração. Uma análise de "
                 "série temporal por empresa vê uma quebra; a análise correta é do GRUPO. É a "
                 "armadilha de continuidade de série do book.",
    ),
    dict(
        chave="mesmo_rotulo_duas_secoes",
        o_que="«Outros créditos» aparece no Ativo Circulante E no Ativo Não Circulante da "
              "Serraria, com o mesmo texto e valores diferentes.",
        porque="Curto e longo prazo da mesma natureza. É como sai do balancete.",
        resposta="São DUAS contas. Um extrator que use o rótulo como chave funde as duas e perde "
                 "uma delas — e o balanço continua fechando, porque a diferença vai para a seção "
                 "errada. É a razão de a hierarquia (`secao` = agrupador imediato) existir.",
    ),
    dict(
        chave="nove_grafias_de_caixa",
        o_que="O disponível tem NOVE grafias no grupo: «Disponibilidades», «Caixa e bancos», "
              "«Caixa e Bancos», «Cx. e bancos», «Numerário disponível», «Bancos», «Bancos conta "
              "movimento», «Caixa e equivalentes», «Caixa, bancos e aplicações de liquidez "
              "imediata». Três delas diferem só por maiúscula e abreviação.",
        porque="Cada empresa tem o seu plano de contas, e o grupo trocou de escritório contábil "
               "na virada de 2023 para 2024.",
        resposta="É UM conceito, em nove empresas. Normalizar demais funde empresas distintas; "
                 "não normalizar nada trata o mesmo conceito como nove. A resposta certa é "
                 "reconhecer o conceito SEM perder a entidade.",
    ),
    dict(
        chave="conta_renomeada_no_meio",
        o_que="A mesma conta muda de nome entre 2023 e 2024 em quase todas as empresas "
              "(«Clientes mercado interno» vira «Duplicatas a receber - mercado interno», "
              "«Provisão para créditos de liquidação duvidosa» vira «Perdas estimadas…»).",
        porque="Troca de escritório contábil e adequação de nomenclatura ao CPC.",
        resposta="É a MESMA conta ao longo da série. Tratar como duas quebra o histórico "
                 "exatamente no meio — e o histórico é o insumo do modelo.",
    ),
    dict(
        chave="conta_que_nasce_e_morre",
        o_que="Contas que existem em parte do período: antecipação de recebíveis (a partir de "
              "2024), direito de uso CPC 06 (a partir de 2024), reserva de lucros a realizar "
              "(some em 2024), reserva legal (some em 2025), ACC da Comercial (some em 2025).",
        porque="A empresa passou a antecipar recebíveis, adotou o CPC 06 R2, consumiu as reservas "
               "para absorver prejuízo e perdeu o limite de câmbio.",
        resposta="Coluna VAZIA no comparativo é «não existia», não «era zero». Preencher zero "
                 "afirma sobre o negócio algo que o documento não diz.",
    ),
    dict(
        chave="dois_minoritarios",
        o_que="A participação de não controladores no combinado vem de DUAS empresas "
              "(AR Transportes 30% e Araucária Varejo 45%), e fica NEGATIVA a partir de 2024.",
        porque="As duas passam a ter patrimônio líquido negativo.",
        resposta="O total só fecha se as duas forem calculadas certo e o sinal for respeitado. "
                 "Com uma origem só, errar a base ainda podia acertar o total por acidente.",
    ),
    dict(
        chave="mutuo_em_duas_secoes",
        o_que="O mútuo com a controladora está no Passivo Circulante em algumas empresas e no "
              "Não Circulante em outras.",
        porque="O vencimento é indeterminado e cada contador decidiu diferente.",
        resposta="Procurar em um lugar só devolve ZERO para metade do grupo — e o combinado "
                 "continua fechando, só inflado dos dois lados. Silêncio, de novo.",
    ),
    dict(
        chave="razao_social_alternativa",
        o_que="A mesma empresa aparece com duas razões sociais entre documentos "
              "(«ARAUCÁRIA FLORESTAL E REFLORESTAMENTO LTDA.» × «Campos Gerais Reflorestamento "
              "Ltda.»), e existe uma OUTRA empresa chamada «CAMPOS GERAIS AGROPECUÁRIA LTDA.».",
        porque="Alteração contratual de razão social em 2023; a grafia antiga sobrevive em "
               "documentos emitidos depois.",
        resposta="O CNPJ desempata. Casar por nome funde duas empresas diferentes — e é o caso "
                 "que a entidade fantasma da v48 já custou uma vez.",
    ),
    dict(
        chave="escala_misturada",
        o_que="As demonstrações estão em R$ mil; o faturamento, o mapa de dívida e os extratos "
              "estão em REAIS; o estoque tem coluna em m³ e unidade; a folha tem coluna em "
              "PESSOAS.",
        porque="Cada relatório sai de um sistema diferente, com a escala daquele sistema.",
        resposta="A escala é do DOCUMENTO, não do kit. Herdar a escala do balanço transforma "
                 "279 funcionários em R$ 279 mil.",
    ),
    dict(
        chave="documento_sem_valor",
        o_que="Certidões, organograma, contrato social e parecer do auditor não rendem NENHUMA "
              "linha financeira.",
        porque="Não são demonstrações. Fazem parte do kit assim mesmo.",
        resposta="Zero linha é o resultado CERTO, não extração falha. E o parecer e as notas "
                 "carregam FATO MATERIAL em texto — covenant rompido, ressalva, continuidade "
                 "operacional —, que é outro canal.",
    ),
    dict(
        chave="nome_de_arquivo_mudo",
        o_que="Boa parte dos arquivos chega sem dizer empresa nem período: «Doc1.pdf», "
              "«digitalizado_20260115_0007.pdf», «ANEXO IV - planilha final REV3.pdf», "
              "«balanço 2024 (1).pdf», «WhatsApp Image 2026-01-14.pdf».",
        porque="É como o cliente manda.",
        resposta="A empresa e o período têm de sair do CONTEÚDO. O nome do arquivo é pista, "
                 "não fonte — e nesses casos ele não é nem pista.",
    ),
    dict(
        chave="periodo_fora_de_ordem",
        o_que="O kit traz balanços de 2022 depois dos de 2025, e comparativos com recortes "
              "diferentes (2025×2024, 2024×2023, 2025×2024×2023×2022, e exercícios isolados).",
        porque="O kit foi montado em pastas por assunto, não por data.",
        resposta="A ordem de chegada não é a ordem cronológica, e o mesmo exercício aparece em "
                 "vários documentos com recortes diferentes. O período tem de sair do conteúdo.",
    ),
    dict(
        chave="mutuos_divergentes",
        o_que="A planilha de mútuos não bate com o balanço por R$ 240 mil.",
        porque="O controller esqueceu um aditivo na planilha.",
        resposta="É divergência VERDADEIRA e tem de abrir pendência. O sistema mostra para um "
                 "humano; não corrige sozinho.",
    ),
]


def resumo():
    return [{k: a[k] for k in ("chave", "o_que", "porque", "resposta")} for a in ARMADILHAS]


# Documentos que NÃO podem render linha financeira — a armadilha
# `documento_sem_valor` escrita como DADO, e não só como prosa.
def sem_valor_monetario(nomes):
    return set(nomes)
