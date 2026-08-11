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


def texto(caminho):
    raw = open(caminho, "rb").read()
    saida = []
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", raw, re.S):
        conteudo = _descomprime(m.group(1))
        if not conteudo:
            continue
        for t in re.finditer(rb"\((?:[^()\\]|\\.)*\)\s*Tj|\[(?:[^\[\]\\]|\\.)*\]\s*TJ", conteudo):
            pedaco = t.group(0)
            partes = re.findall(rb"\((?:[^()\\]|\\.)*\)", pedaco)
            linha = b"".join(p[1:-1] for p in partes)
            linha = re.sub(rb"\\([0-7]{3})", lambda m: bytes([int(m.group(1), 8)]), linha)
            linha = linha.replace(b"\\(", b"(").replace(b"\\)", b")").replace(b"\\\\", b"\\")
            if linha.strip():
                # WinAnsi ≈ cp1252 nos acentos que o book usa.
                saida.append(linha.decode("cp1252", errors="replace"))
    return "\n".join(saida)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    print(texto(sys.argv[1]))
