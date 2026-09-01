# Book de teste — GRUPO VERTENTES (gerador)

Gera um **book de demonstrações contábeis sintéticas** de um grupo econômico fictício em
dificuldade financeira severa, para estressar o pipeline de tratamento de dados com complexidade
de vida real.

```bash
pip install reportlab
python3 gerar.py        # escreve ./pdf/ (14 PDFs + GABARITO.json + GUIA_DE_TESTE.md)
```

Leia o `pdf/GUIA_DE_TESTE.md` gerado: ele traz a história do grupo, o que cada documento estressa
no pipeline, o **gabarito** com os valores esperados e as **armadilhas deliberadas**.

## Por que um gerador e não só os PDFs

Os números precisam **fechar**: Ativo = Passivo + PL em cada entidade e no combinado (com
equivalência patrimonial, provisão para passivo a descoberto, eliminações intragrupo e participação
de não controladores), prejuízo da DRE = variação do PL na DMPL, caixa final da DFC = Disponível do
balanço, soma do faturamento = receita bruta da DRE. Escrever isso à mão é insustentável; aqui os
subtotais são **calculados** e as amarrações **validadas por `assert`** — o script falha se algo
deixar de fechar.

Isso também permite gerar **variações** (outro setor, outro grau de estresse, outro número de
empresas) mexendo em pouca coisa:

| Quero mudar | Onde |
|---|---|
| Composição de contas de uma empresa | `dados.py` (as funções `bp_*`) |
| Grau de estresse / patrimônio de cada empresa | `PL_ALVO` em `motor.py` — o passivo é recalibrado para atingir o PL-alvo, preservando a composição curada |
| Participações, nº de empresas, razões sociais | `PARTICIPACAO` e `ENTIDADES` em `dados.py` |
| DRE, DFC, faturamento, dívida, mútuos | `demonstracoes.py` |
| Layout dos PDFs | `render.py` |

## Arquivos

| Arquivo | Papel |
|---|---|
| `dados.py` | Plano de contas por entidade e ano (contas-folha; nenhum total) |
| `motor.py` | Subtotais, calibração por PL-alvo, MEP, eliminações do combinado + **asserts** |
| `demonstracoes.py` | DRE, DFC, DMPL, faturamento, mapa de dívida, mútuos — amarrados ao balanço |
| `render.py` | Renderização em PDF (reportlab) com aparência de demonstração real |
| `gerar.py` | Ponto de entrada: gera os 14 PDFs + gabarito + guia |
| `extrai.py` | Utilitário de verificação: extrai o texto de um PDF gerado (`python3 extrai.py pdf/01_....pdf`) |

## Ressalvas

- Os documentos são **sintéticos** e trazem essa marcação no rodapé. Nomes de empresas, pessoas,
  CNPJ e CRC são fictícios.
- A saída (`pdf/`) **não é versionada** — é determinística, basta rodar o gerador.
- Tudo sai em **PDF**, inclusive mapa de dívida e faturamento, que na vida real chegariam em
  planilha. Quando o suporte a `.xlsx`/`.docx` entrar no `Preparar Conteudo` (ver
  `docs/CUSTO_OPENAI.md` e o roadmap da auditoria), vale gerar essas duas peças em `.xlsx` para
  exercitar aquele caminho.
