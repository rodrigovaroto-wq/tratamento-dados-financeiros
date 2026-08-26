# Book de teste — GRUPO ARAUCÁRIA (gerador)

Terceiro book do repositório: **190 documentos, 14 empresas, 5 exercícios (2021 a 2025)**, de um
grupo madeireiro fictício do Paraná que passou por uma reestruturação societária no meio do
período analisado.

```bash
pip install reportlab
PYTHONPATH=. python3 gerar.py        # escreve ./pdf/ (190 PDFs + GABARITO + MÉTRICAS + GUIA)
node ../../n8n/medir-custo-book.mjs  # quanto o lote custaria, sem gastar nada
```

Leia o `pdf/GUIA_DE_TESTE.md` gerado: ele traz a história do grupo, o que cada documento estressa,
o gabarito e as **15 armadilhas deliberadas**, cada uma com a resposta certa.

## Por que existe um terceiro book

Os dois anteriores medem se a **extração acerta os números**. O `book-vertentes` é o caso em que a
extração é fiel e nada deve abrir pendência; o `book-canastra` é o caso de um kit real bem
organizado, com 15 armadilhas de leitura. Nenhum dos dois mede o que a v48 mostrou ser o custo real:
**um kit que contradiz a si mesmo sem que nenhum documento esteja errado.**

> **BAGUNÇADO NÃO É INCOMPLETO, E NÃO É INCONSISTENTE.**

Cada balanço fecha. O combinado fecha nos cinco exercícios. Nenhum anexo digita o próprio total. O
que é bagunçado é a **leitura** — nomes, versões, escalas, recortes e vigências. E cada conflito tem
**resposta certa** no gabarito, porque conflito sem resposta certa não é teste, é ruído — e ruído
não mede nada, já que qualquer saída passa.

| | `book-vertentes` | `book-canastra` | `book-araucaria` |
|---|---|---|---|
| Documentos | 14 | 38 | **190** |
| Empresas | 5 | 6 | **14** |
| Exercícios | 2 | 3 | **5** |
| Contas-folha | ~60 | ~100 | **~330** |
| Páginas | 18 | 49 | **247** |
| Linhas com número | ~900 | 3.034 | **16.081** |
| Empresa que nasce ou morre no período | não | não | **três** |
| Sócios minoritários | 0 | 1 | **2** |
| Dois documentos do mesmo período que discordam | não | não | **sim, e os dois fecham** |

## A pergunta que este book faz

Não é «a extração acertou os números?» — os dois anteriores já respondem essa. É:

> **O sistema percebe que dois documentos do mesmo período discordam, e escolhe o certo dizendo
> por quê?**

A armadilha central é o **combinado preliminar**: o controller fechou o combinado reconhecendo só
os pares intragrupo óbvios, e o auditor achou os outros seis depois. As duas versões circularam e
estão no kit. A preliminar infla o ativo do grupo em até R$ 32,8 milhões — e **fecha**, porque
ativo e passivo caem na mesma medida quando um par deixa de ser eliminado. Um sistema que só
confere `Ativo = Passivo + PL` dá as duas por boas.

## Como os números se sustentam

Nenhum total é digitado. O `motor.py` soma as contas-folha e resolve a conta de resultados
acumulados para que **Ativo = Passivo + PL** nas 14 empresas, nos cinco exercícios e no combinado
dos cinco — com `assert` em cada passo. A partir daí, cada anexo **lê** o balanço.

Três capacidades que os motores anteriores não tinham, e que a história deste grupo exige:

| Capacidade | Por quê |
|---|---|
| `ANOS_ATIVOS` por empresa | Três empresas não existem nos cinco exercícios (uma incorporada, duas constituídas no meio). Empresa incorporada não vira coluna de zeros: ela **some** da tabela, que é o que o documento faz |
| `INTRAGRUPO` declarativo | Com 11 pares, esquecer um não quebra nada visível — o combinado continua fechando, inflado dos dois lados. A tabela é lida dos dois lados, e o par cujo credor não existe no exercício não entra |
| Dois minoritários | Com uma origem só de participação de não controladores, errar a base ainda podia acertar o total por acidente |

## O exercício de 2021 é DERIVADO

Nos exercícios de 2022 a 2025 cada saldo é uma escolha curada, conta a conta. O de **2021 é
construído para trás** a partir de 2022, por uma regra declarada grupo de contas a grupo de contas
(`RETRO`, em `dados.py`). Ele fecha como os outros, mas o que ele prova é que a **série tem cinco
pontos e uma direção coerente**, não que cada saldo individual seja interessante.

O que ele acrescenta é decisivo assim mesmo: com quatro exercícios o kit já começava na descida;
com cinco, o **pico fica dentro da janela** — o PL combinado vai de 436.847 para 29.637 (R$ mil).

## Determinismo

**No conteúdo, e não byte a byte.** Duas rodadas dão o mesmo texto nos 190 PDFs e o mesmo
`GABARITO.json` — medido comparando o hash do `TEXTO_EXTRAIDO.json`. Os arquivos não são idênticos
byte a byte porque o reportlab carimba data de criação e ID em cada PDF; isso vale também para os
dois books anteriores.

O gerador **apaga o `pdf/` antes de escrever**. Não é higiene: o número de documentos e os nomes
deles dependem do número de exercícios e de empresas, e quando o histórico passou de quatro para
cinco anos o diretório ficou com os 190 novos E os 190 antigos — 380 arquivos, com nomes parecidos e
períodos diferentes, contando duas histórias. Um book velho misturado com o novo é pior que book
nenhum, porque parece certo.

## Arquivos

| Arquivo | Papel |
|---|---|
| `dados.py` | As 14 empresas, o plano de contas por entidade e exercício, a tabela `INTRAGRUPO` e a regra `RETRO` de 2021 |
| `motor.py` | Subtotais, vigência por empresa, MEP, eliminações do combinado, participação de não controladores + **asserts** |
| `demonstracoes.py` | DRE, DFC, DMPL, DVA, faturamento, dívida, mútuos, aging, estoque, fiscal, contingências, imobilizado, folha, extratos — todos amarrados ao balanço |
| `bagunca.py` | **As 15 armadilhas, catalogadas com resposta certa**, e o combinado preliminar |
| `render.py` | Renderização em PDF (reportlab) |
| `gerar.py` | Ponto de entrada: os 190 PDFs por família, o gabarito, as métricas e o guia |
| `extrai.py` | Utilitário de verificação: extrai o texto de um PDF gerado |

## Ressalvas

- Os documentos são **sintéticos** e trazem essa marcação no rodapé. Nomes de empresas, pessoas,
  CNPJ e CRC são fictícios.
- A saída (`pdf/`) **não é versionada** — basta rodar o gerador.
- Tudo sai em **PDF**, inclusive mapa de dívida e faturamento, que na vida real chegariam em
  planilha.
