#!/usr/bin/env python3
"""
MAPEIA UM .XLSX POR DENTRO — o instrumento para espelhar o Modelo Base.

POR QUE NÃO USAR O exceljs PARA ISTO. O `exceljs` (que o export usa para
ESCREVER) carrega a planilha inteira em memória e estourou o heap do Node ao
abrir o Modelo Base e o nosso export na mesma execução (heap limit, 8 GB). Um
`.xlsx` é um ZIP de XML: ler as partes direto é ordens de grandeza mais barato,
não depende de dependência nenhuma, e mostra coisas que o exceljs esconde —
nomes definidos, validação de dados, formatação condicional, painéis
congelados, gráficos e imagens.

ATENÇÃO A UMA ARMADILHA QUE JÁ PRODUZIU NÚMERO ERRADO AQUI: a ordem das abas no
workbook NÃO é a ordem de `sheet1.xml`, `sheet2.xml`… O vínculo correto é
`xl/workbook.xml` → `r:id` → `xl/_rels/workbook.xml.rels` → `Target`. Mapear por
índice de arquivo atribui a contagem de fórmulas de uma aba a outra — foi o que
aconteceu na primeira medição desta sessão, e por isso este script existe em vez
de um `grep` improvisado.

USO:

    python3 docs/referencia/mapear-xlsx.py <arquivo.xlsx> [--aba NOME] [--celulas]

    # resumo de todas as abas (fórmulas, validações, formatação condicional…)
    python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx

    # tudo o que existe numa aba, célula a célula, com fórmula e estilo
    python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx \
        --aba "Balance Sheet" --celulas
"""
import sys
import os
import zipfile
from xml.etree import ElementTree as ET

M = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PR = "http://schemas.openxmlformats.org/package/2006/relationships"


def abas(z):
    """[(nome, estado, caminho_da_parte)] na ORDEM do workbook, via rels."""
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = {r.get("Id"): r.get("Target")
            for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels")).iter(f"{{{PR}}}Relationship")}
    out = []
    for s in wb.iter(f"{{{M}}}sheet"):
        alvo = rels[s.get(f"{{{R}}}id")].lstrip("/")
        out.append((s.get("name"), s.get("state", "visible"),
                    alvo if alvo.startswith("xl/") else "xl/" + alvo))
    return out


def strings(z):
    """A tabela de strings compartilhadas — sem ela toda célula de texto é um número."""
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    raiz = ET.fromstring(z.read("xl/sharedStrings.xml"))
    return ["".join(t.text or "" for t in si.iter(f"{{{M}}}t")) for si in raiz.iter(f"{{{M}}}si")]


def resumo(caminho):
    z = zipfile.ZipFile(caminho)
    nomes = z.namelist()
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    definidos = [d.get("name") for d in wb.iter(f"{{{M}}}definedName")]
    print(f"\n===== {caminho} — {os.path.getsize(caminho)/1e6:.1f} MB =====")
    print(f"nomes definidos: {len(definidos)}"
          + (f"   ex.: {definidos[:6]}" if definidos else ""))
    print(f"gráficos: {sum(1 for n in nomes if '/charts/chart' in n)}  "
          f"imagens: {sum(1 for n in nomes if '/media/' in n)}  "
          f"estilos: {'xl/styles.xml' in nomes}  tema: {'xl/theme/theme1.xml' in nomes}")
    total = 0
    for nome, estado, parte in abas(z):
        raw = z.read(parte)
        f = raw.count(b"<f>") + raw.count(b"<f ")
        total += f
        print(f"  {nome[:34]:34s} {estado:8s} kb={len(raw)//1024:>5} fórmulas={f:>5} "
              f"validações={raw.count(b'<dataValidation '):>3} "
              f"cond={raw.count(b'<conditionalFormatting'):>3} "
              f"merges={raw.count(b'<mergeCell '):>3} congelado={b'<pane ' in raw}")
    print(f"  TOTAL de fórmulas: {total}")


def celulas(caminho, aba):
    z = zipfile.ZipFile(caminho)
    sst = strings(z)
    alvo = next((p for n, _, p in abas(z) if n == aba), None)
    if not alvo:
        print(f"aba '{aba}' não existe. Abas: {[n for n, _, _ in abas(z)]}")
        return
    raiz = ET.fromstring(z.read(alvo))
    for pane in raiz.iter(f"{{{M}}}pane"):
        print(f"# painel congelado: xSplit={pane.get('xSplit')} ySplit={pane.get('ySplit')} "
              f"topLeft={pane.get('topLeftCell')}")
    for mc in raiz.iter(f"{{{M}}}mergeCell"):
        print(f"# merge: {mc.get('ref')}")
    for dv in raiz.iter(f"{{{M}}}dataValidation"):
        f1 = next((t.text for t in dv.iter(f"{{{M}}}formula1")), None)
        print(f"# validação: {dv.get('sqref')} tipo={dv.get('type')} f1={f1}")
    for cf in raiz.iter(f"{{{M}}}conditionalFormatting"):
        regras = [(r.get("type"), r.get("operator"),
                   [t.text for t in r.iter(f"{{{M}}}formula")]) for r in cf.iter(f"{{{M}}}cfRule")]
        print(f"# formatação condicional: {cf.get('sqref')} {regras}")
    print("célula | estilo | tipo | fórmula | valor")
    for c in raiz.iter(f"{{{M}}}c"):
        ref, t, s = c.get("r"), c.get("t"), c.get("s", "")
        f = c.find(f"{{{M}}}f")
        v = c.find(f"{{{M}}}v")
        formula = ("=" + (f.text or "")) if f is not None else ""
        if f is not None and f.get("t") == "shared" and not f.text:
            formula = f"=(compartilhada si={f.get('si')})"
        valor = v.text if v is not None else ""
        if t == "s" and valor.isdigit():
            valor = sst[int(valor)]
        if t == "inlineStr":
            valor = "".join(x.text or "" for x in c.iter(f"{{{M}}}t"))
        if not formula and valor == "":
            continue
        print(f"{ref} | s={s} | {t or 'n'} | {formula} | {valor}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    arq = sys.argv[1]
    if "--aba" in sys.argv:
        nome = sys.argv[sys.argv.index("--aba") + 1]
        if "--celulas" in sys.argv:
            celulas(arq, nome)
        else:
            resumo(arq)
    else:
        resumo(arq)
