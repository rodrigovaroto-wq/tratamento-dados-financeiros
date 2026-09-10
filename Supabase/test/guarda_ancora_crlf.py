#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# Guarda de repositório — a 0163 nasceu porque a 0161 e a 0162 patchavam
# fn_registrar_diagnostico por ÂNCORA sobre pg_get_functiondef() SEM tolerância
# a CRLF, enquanto a 0160 (mesma função, mesma técnica) já sabia que precisava:
# o corpo publicado em PRODUÇÃO pode estar gravado com `\r\n` (basta o texto ter
# passado por um editor ou colagem do Windows uma vez, e fica assim para
# sempre — `pg_get_functiondef` devolve o que está gravado, não normaliza).
#
# MEDIDO: `tem_0161=false` e `tem_0162` nunca aplicada em produção, com a
# mensagem `"o bloco do format() de periodo_incorreto não foi encontrado UMA
# vez (achei 0)"` — reproduzido nesta árvore convertendo o corpo do banco
# `tdf_0160` para CRLF e rodando a 0161 sobre ele: mensagem IDÊNTICA. A causa:
# a 0160 usa `regexp_matches`/`regexp_replace` com `\r?\n` entre os fragmentos
# de linha do padrão (o `?` torna o `\r` opcional, casando tanto LF quanto
# CRLF); a 0161 e a 0162 nunca tinham `\r?` em padrão nenhum. **Passa em toda
# suíte local** porque o `Supabase/test/run.sh` monta o corpo do zero, sempre
# em LF — só o banco de produção, com histórico de edição, expõe o buraco.
#
# ESTE ARQUIVO NÃO CONSERTA A 0161 NEM A 0162 — migration aplicável é
# imutável, e a correção real é a reemissão inteira da 0163 (ver seu
# cabeçalho). O que este arquivo impede é a PRÓXIMA migration nascer com o
# mesmo buraco: varre `Supabase/migrations/*.sql` procurando toda chamada a
# `regexp_matches`/`regexp_replace` cujo primeiro argumento evidencia que o
# alvo é o corpo publicado de uma função (o arquivo cita `pg_get_functiondef`)
# e cujo padrão é MULTI-LINHA — contém, no texto bruto do padrão, uma quebra
# de linha real (dentro de string com dollar-quote) ou a sequência de duas
# letras `\n` (dentro de string simples ou `E''`, onde o motor de regex do
# Postgres lê isso como "found de linha"). Um padrão multi-linha SEM `\r?`
# imediatamente antes de cada `\n` só casa contra corpo LF — exatamente o
# defeito da 0161/0162.
#
# ESCOPO DELIBERADAMENTE ESTREITO: só `regexp_matches`/`regexp_replace`. A
# 0161/0162 corrigiam o corpo com `replace()` LITERAL (não regex) — aí `\r?`
# não teria significado nenhum (replace não interpreta regex), e o guarda não
# as acusa: reescrever essas duas migrations está fora do escopo da 0163 (elas
# já foram aplicadas nesta árvore e não se mexe em migration aplicada). O que
# este guarda proíbe é a PRÓXIMA migration repetir a forma que a 0160 já
# tinha acertado.
#
# MEDIDO NÃO-VAZIO: rode este arquivo apontando para uma cópia de
# `Supabase/migrations/0160_....sql` com todo `\r?` removido do `v_pat` — ele
# reprova, citando o arquivo e a variável. Rodando contra o diretório real
# (0160 com `\r?` como está, e 0161/0162 que não usam regexp para o patch
# principal), ele passa. Ver a mensagem de reprovação registrada no commit.
# -----------------------------------------------------------------------------
import re
import sys
from pathlib import Path


def achar_string(texto, i):
    """A partir de texto[i] (que é uma aspa simples ou o '$' de um dollar-quote),
    devolve (conteudo_bruto, indice_apos_a_string). `conteudo_bruto` é o texto
    ENTRE os delimitadores, sem interpretar escapes — é só isso que os
    detectores abaixo precisam (procurar '\n' e '\r?' como texto)."""
    if texto[i] == "'":
        j = i + 1
        while j < len(texto):
            if texto[j] == "'":
                if j + 1 < len(texto) and texto[j + 1] == "'":
                    j += 2
                    continue
                return texto[i + 1:j], j + 1
            j += 1
        raise ValueError("string simples não fechada")
    if texto[i] == "$":
        m = re.match(r"\$[A-Za-z_]*\$", texto[i:])
        if not m:
            raise ValueError("'$' que não abre dollar-quote")
        tag = m.group(0)
        fim_abertura = i + len(tag)
        fim = texto.find(tag, fim_abertura)
        if fim == -1:
            raise ValueError(f"dollar-quote {tag} não fechado")
        return texto[fim_abertura:fim], fim + len(tag)
    raise ValueError("posição não é início de string")


def pular_espacos_e_concat(texto, i):
    """Avança por espaço em branco e pelo operador de concatenação `||`,
    parando no próximo caractere que não é um dos dois (tipicamente o início
    da próxima string do lado direito de um `:=`, ou o `E` de `E'...'`)."""
    n = len(texto)
    while i < n:
        if texto[i].isspace():
            i += 1
        elif texto[i:i + 2] == "||":
            i += 2
        elif texto[i] == "E" and i + 1 < n and texto[i + 1] == "'":
            i += 1  # o prefixo E fica, a aspa simples é tratada por achar_string
        else:
            break
    return i


def resolver_expressao_ate_ponto_e_virgula(texto, i):
    """A partir de logo após `:=`, concatena o CONTEÚDO BRUTO de cada string
    literal (dollar-quoted ou simples/E'') encontrada, na ordem, até o `;` de
    topo de nível que encerra a atribuição. Ignora texto fora de string (o
    `||` e espaços) — não é executado, só concatenado para procurar padrão."""
    n = len(texto)
    pedacos = []
    while i < n:
        c = texto[i]
        if c in ("'", "$"):
            bruto, i = achar_string(texto, i)
            pedacos.append(bruto)
            i = pular_espacos_e_concat(texto, i)
            continue
        if c == ";":
            return "".join(pedacos), i + 1
        if c.isspace():
            i += 1
            continue
        # qualquer outro caractere fora de string antes do ';' (não esperado
        # nestas migrations, mas não é este guarda quem valida SQL) — avança.
        i += 1
    raise ValueError("';' de fechamento não encontrado")


def resolver_argumento_literal_ou_var(arg_bruto, texto, pos_chamada):
    """`arg_bruto` é o texto exato do argumento (2º) da chamada, já com
    parênteses/vírgulas de topo de nível removidos. Se for um identificador
    simples, procura a ÚLTIMA atribuição `<var> [constant] text := ...;`
    ANTES da chamada e devolve o conteúdo bruto concatenado dela. Senão,
    resolve o próprio `arg_bruto` como uma (possível concatenação de)
    string(s) literal(is)."""
    arg = arg_bruto.strip()
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", arg):
        padrao_decl = re.compile(
            r"\b" + re.escape(arg) + r"\b\s*(?:constant\s+)?text\s*:=\s*"
        )
        ultima = None
        for m in padrao_decl.finditer(texto, 0, pos_chamada):
            ultima = m
        if ultima is None:
            return None  # variável declarada em outro lugar (ex.: outro arquivo) — não é este caso aqui
        bruto, _ = resolver_expressao_ate_ponto_e_virgula(texto, ultima.end())
        return bruto
    # argumento é literal (ou concatenação) diretamente no local da chamada.
    conteudo, _ = resolver_expressao_ate_ponto_e_virgula(arg + ";", 0)
    return conteudo


def dividir_argumentos_top_level(texto, i):
    """`texto[i]` é o primeiro caractere após o '(' de abertura da chamada.
    Devolve (lista_de_argumentos_brutos, indice_apos_o_')'_de_fechamento),
    respeitando parênteses e strings aninhados."""
    args = []
    atual_ini = i
    profundidade = 0
    n = len(texto)
    while i < n:
        c = texto[i]
        if c in ("'", "$"):
            _, i = achar_string(texto, i)
            continue
        if c == "(":
            profundidade += 1
            i += 1
            continue
        if c == ")":
            if profundidade == 0:
                args.append(texto[atual_ini:i])
                return args, i + 1
            profundidade -= 1
            i += 1
            continue
        if c == "," and profundidade == 0:
            args.append(texto[atual_ini:i])
            atual_ini = i + 1
            i += 1
            continue
        i += 1
    raise ValueError("chamada sem ')' de fechamento")


def eh_padrao_multilinha(padrao_bruto):
    """Multi-linha = contém quebra de linha real OU a sequência de duas letras
    '\\n' — nos dois casos o regex do Postgres vai tentar casar um fim de
    linha do corpo publicado."""
    return ("\n" in padrao_bruto) or ("\\n" in padrao_bruto)


def tem_r_opcional(padrao_bruto):
    return "\\r?" in padrao_bruto


def checar_arquivo(caminho):
    texto = caminho.read_text(encoding="utf-8")
    if "pg_get_functiondef" not in texto:
        return []  # esta migration não patcheia corpo de função nenhuma

    violacoes = []
    for m in re.finditer(r"\b(regexp_matches|regexp_replace)\s*\(", texto):
        pos_args = m.end()
        try:
            args, _ = dividir_argumentos_top_level(texto, pos_args)
        except ValueError:
            continue
        if len(args) < 2:
            continue
        arg_padrao = args[1]
        try:
            padrao_bruto = resolver_argumento_literal_ou_var(arg_padrao, texto, m.start())
        except ValueError:
            continue
        if padrao_bruto is None:
            continue
        if eh_padrao_multilinha(padrao_bruto) and not tem_r_opcional(padrao_bruto):
            linha = texto.count("\n", 0, m.start()) + 1
            violacoes.append(
                f"{caminho}:{linha}: {m.group(1)}(...) com padrão MULTI-LINHA (arg 2 = "
                f"`{arg_padrao.strip()}`) sem `\\r?` — casa em LF, acha ZERO num corpo "
                f"gravado com CRLF (o defeito da 0161/0162, ver 0163)."
            )
    return violacoes


def main():
    if len(sys.argv) > 1:
        diretorio = Path(sys.argv[1])
    else:
        raiz = Path(__file__).resolve().parents[2]
        diretorio = raiz / "Supabase" / "migrations"

    arquivos = sorted(diretorio.glob("*.sql"))
    if not arquivos:
        print(f"FALHOU: nenhuma migration encontrada em {diretorio}")
        return 1

    todas_violacoes = []
    for f in arquivos:
        todas_violacoes.extend(checar_arquivo(f))

    if todas_violacoes:
        print("FALHOU: âncora multi-linha sem tolerância a CRLF (\\r?) — casa em LF, acha ZERO em produção:")
        for v in todas_violacoes:
            print(f"   {v}")
        print("   Acrescente `\\r?` antes de cada `\\n` do padrão (é o que a 0160 já faz).")
        return 1

    print(f"   {len(arquivos)} migrations sem âncora multi-linha frágil a CRLF")
    return 0


if __name__ == "__main__":
    sys.exit(main())
