# Como usar a memória deste projeto

Duas camadas, com propósitos diferentes:

- **`MEMORY.md`** — o índice, **sempre carregado**. Uma linha por entrada, com a descrição
  dizendo o que a entrada ensina. Teto mole de **130 linhas não vazias**. Ele é pequeno de
  propósito: índice que ninguém lê até o fim não é memória, é peso.
- **`ESTADO.md` / `HANDOFF.md`** — a camada de longo prazo, sem teto, lida sob demanda. É para
  onde uma entrada migra quando deixa de merecer o espaço nobre do índice.

## O que vira memória

O teste é literal, e é restritivo de propósito:

> **Uma sessão futura ficaria surpresa e grata de saber disso antes de começar, em vez de
> descobrir do jeito difícil?**

Não vira memória:

- qualquer coisa derivável lendo o código ou o `git log`;
- prazo, motivação, contexto temporário desta rodada;
- receita de debug — isso mora na mensagem do commit;
- o que já está no `CLAUDE.md` (duplicar cria duas fontes que dessincronizam).

Vira memória: erro que precisou de correção repetida, padrão de arquitetura descoberto só depois
de tentativa falha, regra de negócio invisível no código, e onde mora uma informação que não
está neste repositório.

**Erre para o lado de não salvar.**

## Formato

Um arquivo por entrada, `kebab-case.md`, com frontmatter:

```markdown
---
name: slug-em-kebab-case
description: uma linha — é a única parte lida automaticamente todo dia; capriche nela
metadata:
  type: feedback | architecture | business-rule | reference
---
```

Os quatro `type` são fechados. Se uma entrada não cabe em nenhum, provavelmente ela não devia
ser memória.

## Política de crescimento

Passou de 130 linhas não vazias no índice, **antes** de acrescentar a próxima entrada:

1. pontue as existentes por recência × especificidade × chance de evitar um erro real;
2. para cada entrada de baixa pontuação, **migre — nunca apague direto**, nesta ordem:
   1. procure o mesmo assunto no `ESTADO.md`/`HANDOFF.md` e **estenda** em vez de duplicar;
   2. escreva no formato daquele arquivo (prosa com o número medido junto, como o resto dele);
   3. crie a seção;
   4. **leia de volta** para confirmar;
   5. **só então** apague o arquivo de tópico e a linha do índice.
3. reescreva o índice com o que sobrou, e só aí acrescente a entrada nova.

Apagar antes da leitura de confirmação é perda de dado, não faxina. Na dúvida se uma entrada
ainda merece o lugar, deixe: migrar depois não custa nada.
