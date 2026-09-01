# -*- coding: utf-8 -*-
"""Extrai o texto de um PDF gerado, para conferir a olho o que a extração vai ler.

    python3 extrai.py pdf/01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf

Sem dependência externa: lê os streams de conteúdo do próprio PDF. Serve para
responder rápido "o número saiu na página?" sem abrir um leitor.
"""

import base64
import re
import sys
import zlib


def _descomprime(bruto):
    """O reportlab escreve ASCII85 + Flate por padrão; um PDF de outra origem
    pode vir só com Flate ou cru. Tenta as três, na ordem, e desiste em silêncio
    (stream de fonte não é texto e não deve derrubar a leitura)."""
    for tentativa in (
        lambda b: zlib.decompress(base64.a85decode(b.strip(), adobe=True)),
        lambda b: zlib.decompress(b),
        lambda b: b,
    ):
        try:
            saida = tentativa(bruto)
            if b"Tj" in saida or b"TJ" in saida:
                return saida
        except Exception:
            continue
    return b""


def _decodifica(pedaco):
    partes = re.findall(rb"\((?:[^()\\]|\\.)*\)", pedaco)
    linha = b"".join(p[1:-1] for p in partes)
    linha = re.sub(rb"\\([0-7]{3})", lambda m: bytes([int(m.group(1), 8)]), linha)
    linha = linha.replace(b"\\(", b"(").replace(b"\\)", b")").replace(b"\\\\", b"\\")
    # WinAnsi ≈ cp1252 nos acentos que o book usa.
    return linha.decode("cp1252", errors="replace")


def texto(bruto):
    """Um pedaço de texto por operador de escrita — é uma CÉLULA, não uma linha.

    Uma tabela do reportlab escreve cada célula com o seu próprio `Tj`, então a
    linha "Caixa e equivalentes | 1.234 | 2.345" sai como TRÊS pedaços aqui.
    Serve para conferir se o número saiu na página; NÃO serve para contar linha
    de conta — para isso existe `linhas()` abaixo."""
    saida = []
    for conteudo in _fluxos(bruto):
        for t in re.finditer(rb"\((?:[^()\\]|\\.)*\)\s*Tj|\[(?:[^\[\]\\]|\\.)*\]\s*TJ", conteudo):
            pedaco = _decodifica(t.group(0))
            if pedaco.strip():
                saida.append(pedaco)
    return "\n".join(saida)


def _fluxos(bruto):
    """Os fluxos de conteúdo do PDF, a partir dos BYTES — não de um caminho.

    ESTA FUNÇÃO NÃO ABRE ARQUIVO, e a mudança não é estilo. Ela abria
    (`open(caminho, "rb")`), e os dois `gerar.py` já tinham lido o mesmo arquivo
    linhas antes: o PDF era lido TRÊS vezes por documento (uma no `gerar.py`, uma
    em `texto()` e uma em `linhas()`). Recebendo bytes, a leitura acontece uma vez
    só, no chamador que já a fazia.

    E o efeito de lado é o que o `pythonsecurity:S8707` cobrava: sem acesso a
    disco aqui, não há caminho vindo de fora para validar — o sink deixa de
    existir em vez de ganhar mais uma guarda. É a diferença entre validar a
    entrada e não precisar dela.
    """
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", bruto, re.S):
        conteudo = _descomprime(m.group(1))
        if conteudo:
            yield conteudo


# Ops de texto na ORDEM em que aparecem no fluxo: posicionamento (Tm/Td/TD/T*)
# e escrita (Tj/TJ). É a ordem que amarra cada pedaço à sua coordenada.
_OPS = re.compile(
    rb"(?P<tm>[-\d.]+\s+[-\d.]+\s+[-\d.]+\s+[-\d.]+\s+(?P<tmx>[-\d.]+)\s+(?P<tmy>[-\d.]+)\s+Tm)"
    rb"|(?P<td>(?P<tdx>[-\d.]+)\s+(?P<tdy>[-\d.]+)\s+(?:Td|TD))"
    rb"|(?P<tstar>T\*)"
    rb"|(?P<txt>\((?:[^()\\]|\\.)*\)\s*Tj|\[(?:[^\[\]\\]|\\.)*\]\s*TJ)"
)

# Quanto dois pedaços podem diferir em Y e ainda serem a MESMA linha. 2 pontos
# ≈ um quarto da altura da fonte de 7,2pt usada nas tabelas do book: acomoda o
# arredondamento do reportlab sem juntar duas linhas de tabela (que ficam a
# ~10pt uma da outra).
TOLERANCIA_Y = 2.0


def _pedacos_com_coordenada(conteudo):
    """Cada pedaço de texto do fluxo com a coordenada (y, x) onde ele foi escrito.

    Saiu de dentro de `linhas()` porque as duas responsabilidades são distintas —
    ler a posição de cada pedaço, e agrupar pedaços em linha — e juntas passavam
    de 15 de complexidade cognitiva (`python:S3776`, medido em 20). A regra não
    mudou uma vírgula: é o mesmo laço, com o mesmo estado de x/y.
    """
    pedacos = []  # (y, x, texto)
    x = y = 0.0
    for m in _OPS.finditer(conteudo):
        if m.group("tm"):
            x, y = float(m.group("tmx")), float(m.group("tmy"))
        elif m.group("td"):
            x += float(m.group("tdx"))
            y += float(m.group("tdy"))
        elif m.group("tstar"):
            y -= 1.0
        else:
            texto_pedaco = _decodifica(m.group("txt"))
            if texto_pedaco.strip():
                pedacos.append((y, x, texto_pedaco))
    return pedacos


def linhas(bruto):
    """O texto agrupado em LINHAS, pela coordenada Y de cada pedaço.

    É esta a forma que a extração de PDF do n8n (nó `Extract From File`) entrega
    ao pipeline, e é sobre ela que a régua de cobertura de `N8N/lib/cobertura.mjs`
    decide se um documento veio pela metade. Contar sem agrupar conta CÉLULA e
    não CONTA — uma linha de balanço comparativo de três exercícios viraria
    quatro, e a régua ficaria 4× mais frouxa do que se pensa."""
    saida = []
    for conteudo in _fluxos(bruto):
        pedacos = _pedacos_com_coordenada(conteudo)
        # Y cresce para CIMA no PDF: a primeira linha da página é o maior Y.
        for y_linha in sorted({p[0] for p in pedacos}, reverse=True):
            if saida and any(abs(y_linha - ja) <= TOLERANCIA_Y for ja in saida[-1][0]):
                alvo = saida[-1]
            else:
                alvo = (set(), [])
                saida.append(alvo)
            alvo[0].add(y_linha)
            alvo[1].extend(p for p in pedacos if p[0] == y_linha)
    return [" ".join(t for _, _, t in sorted(pedacos_da_linha, key=lambda p: p[1])).strip()
            for _, pedacos_da_linha in saida]


# NÃO HÁ BLOCO `__main__` AQUI, e a ausência é deliberada.
#
# Existia um: `python3 extrai.py <pdf>` imprimia o texto de um arquivo, e os
# READMEs dos dois books o documentavam. Ele saiu por dois motivos que se somam.
#
# REDUNDÂNCIA: desde que os DOIS geradores passaram a escrever
# `pdf/TEXTO_EXTRAIDO.json`, o texto de todos os documentos já está versionado —
# o utilitário reimprimia, um de cada vez, o que o arquivo inteiro já traz.
#
# E ELE ERA O ÚLTIMO ACESSO A DISCO DESTA BIBLIOTECA. O `pythonsecurity:S8707`
# apontava o `open(sys.argv[1])` dele: caminho vindo da linha de comando indo
# direto para o sistema de arquivos. Com o bloco fora, este módulo não abre
# arquivo nenhum — recebe bytes e devolve texto. Um sink que deixa de existir não
# precisa de validação, e não volta na próxima refatoração.
