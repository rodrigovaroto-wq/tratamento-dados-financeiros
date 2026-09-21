---
id: f2-localizador-chave-pendencia-falsa
tipo: defeito
toca:
  - Supabase/migrations/0185_o_tipo_presente_que_ninguem_conferia.sql
  - Supabase/test/linha_exigida_tipos_variaveis.test.sql
  - Supabase/test/fixture_book_canastra.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
prova: Supabase/test/run.sh
substitui: []
---

# F2.1: Localizador contra `chave` abre pendência FALSA quando termo mora em `secao` (migration 0185)

**Descoberto em:** 21/09/2026 (rodada F2.1, fatia de cobertura de tipos)

**Padrão do defeito:** Um localizador de `taxonomia_linha_exigida` que casa contra `chave` pode abrir uma pendência `entidade_exigencia_insatisfeita` FALSA quando o termo do conceito mora na `secao` do documento em vez da `chave`.

## Evidência

Na migration `0185`, ao adicionar exigências para nove tipos antes mudos, a primeira versão definiu localizadores casando `contra='chave'` para CONTINGENCIAS, HEADCOUNT, EXTRATO_BANCARIO e ESTOQUE. Ao medir contra `Supabase/test/fixture_book_canastra.sql` — documento real de teste — estes quatro tipos davam `satisfeita=false` num caso correto:

- **CONTINGENCIAS**: documento traz "CONTINGÊNCIAS — Provável" na `secao`, não há rótulo em `chave`
- **HEADCOUNT**: documento traz "Headcount" na `secao`, detalhe em `chave`
- **EXTRATO_BANCARIO**: documento traz "SALDOS BANCÁRIOS" na `secao`, descrição de conta em `chave`
- **ESTOQUE**: documento traz "ESTOQUES" na `secao`, SKU/loja em `chave`

Nos quatro casos, o **termo do conceito mora em `secao`**, não em `chave`. O localizador em `chave` buscava nomes próprios e rótulos de detalhe — estrutura certa para alguns tipos (ex. "Demais fornecedores" em AGING_AP), errada para estes quatro.

**Medição:** Rodando `fn_exigencias_do_caso` contra o caso da fixture canastra com os quatro localizadores `contra='chave'` ligados — **4 de 6 tipos presentes na fixture reprovavam**. Com os localizadores trocados para `contra='secao'` em cascata (modelo de múltiplas rotas de busca, já presente na `0113`) — **6 de 6 passavam**. Bloco 2 de teste SQL (Supabase/test/run.sh) prova isso contra documento real.

## Por que importa (regra 6)

Este é exatamente o padrão que causou a `0166` — cinco pendências falsas num lote real por localizar termo na coluna errada. A `0113` já tinha construído o mecanismo de múltiplas rotas (`contra = 'chave' OR contra = 'secao'`), mas esse uso não tinha precedente documentado até agora. **A armadilha é o silêncio:** sem medição contra documento real, um localizador contra `chave` passa em teste sintético onde você **escolhe** os rótulos, e falha quando o documento real **tem outro padrão de layout**.

## O que foi corrigido

- CONTINGENCIAS, HEADCOUNT, EXTRATO_BANCARIO, ESTOQUE: localizador `contra='secao'` adicionado em paralelo ao `contra='chave'`
- AGING_AP, AGING_AR: mantêm `contra='chave'` (residual: "Demais fornecedores", "Demais clientes")
- GARANTIAS, AVAIS_FIANCAS, DEBITOS_TRIB: **SEM MEDIÇÃO CONTRA DOCUMENTO REAL** — não existem em nenhuma das duas fixtures do repositório (registrado como achado não investigado, seção 1.7 do roadmap)

## Lição para próximas fatias

1. **Nunca confiar em teste sintético se o padrão de layout real é desconhecido.** A `0113` documentou bem como buscar por múltiplas rotas, mas a aplicação aqui foi a primeira vez que o mecanismo foi necessário de verdade.
2. **Adicionar `contra='secao'` é barato;** adicionar `contra='chave'` quando não existe em documentos reais é caro — abre pendência falsa e demora meses para descobrir em produção.
3. **Fixture de teste NÃO é substituto para documento real.** A suíte passou com o localizador errado porque a fixture foi construída com rótulos que o teste escolheu. A fixture _canastra_ tem padrão diferente.

## Commits afetados

- `6947e49` — fatia original (numerada 0182), com o defeito
- `ead6434` — renumeração 0182→0185 (sequência de aplicação)
- `1d207ab` — correção dos achados da revisão independente
