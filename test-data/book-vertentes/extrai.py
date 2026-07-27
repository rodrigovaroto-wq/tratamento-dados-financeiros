"""Extrator de texto de PDF do reportlab (ASCII85 + Flate), para verificação."""
import re, zlib, base64, sys

def texto(caminho):
    d = open(caminho, 'rb').read()
    out = []
    for m in re.finditer(rb'stream\r?\n(.*?)endstream', d, re.S):
        raw = m.group(1).rstrip(b'\n').rstrip(b'>').rstrip(b'~')
        try:
            u = zlib.decompress(base64.a85decode(raw, adobe=False, ignorechars=b' \n\r\t'))
        except Exception:
            continue
        for t in re.finditer(rb'\(((?:[^()\\]|\\.)*)\)\s*Tj', u):
            s = t.group(1)
            s = re.sub(rb'\\([0-7]{3})', lambda mm: bytes([int(mm.group(1), 8)]), s)
            s = s.replace(b'\\(', b'(').replace(b'\\)', b')').replace(b'\\\\', b'\\')
            out.append(s.decode('latin-1'))
    return out

if __name__ == '__main__':
    ls = texto(sys.argv[1])
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
    print(f"[{len(ls)} fragmentos]")
    for l in ls[:n]: print(l)
