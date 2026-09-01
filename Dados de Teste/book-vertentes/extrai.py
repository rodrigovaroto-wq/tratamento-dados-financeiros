# -*- coding: utf-8 -*-
"""Aponta para o extrator COMPARTILHADO — este arquivo não tem lógica.

O extrator morava duplicado: `book-canastra/extrai.py` e `book-vertentes/extrai.py`,
124 linhas cada, e a segunda cópia nasceu de um `cp` meu em 01/09 para dar ao
vertentes o agrupamento por coordenada Y que só o canastra tinha. O Sonar acusou
**65,7% de duplicação em código novo** contra um limite de 3%, e estava certo: a
régua dos dois books só vale como segunda opinião se os dois lerem o PDF do MESMO
jeito, e duas cópias divergem no dia em que alguém corrigir uma só.

Agora há um extrator, em `Dados de Teste/comum/extrai.py`, e este arquivo só
resolve o caminho — os books são executados com `cd book-X && PYTHONPATH=.`, então
o pai não está no path por padrão.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from comum.extrai import *  # noqa: F401,F403,E402
from comum.extrai import texto, linhas  # noqa: F401,E402  (os dois usados pelos books)
