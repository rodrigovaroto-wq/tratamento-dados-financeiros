# Captura — tela de Modelagem do caso "Teste v35" (portal em produção, 04/08/2026)

Página salva pelo navegador (*Salvar como → Página completa*) a partir de

```
https://tratamento-dados-financeiros.vercel.app/casos/c4581e51-3ee5-413d-ba04-6d6149fff0c7/modelagem
```

com a `0042`/`0043`/`0044` **já aplicadas** no Supabase — é a primeira evidência de como a Fase 8
se comporta contra o dado real, e não contra a fixture.

## O que é cada arquivo

| Arquivo | Serve para |
|---|---|
| `Oria · Tratamento de Dados Financeiros.html` | **é o artefato.** O HTML renderizado pelo servidor traz o estado inteiro da tela: parâmetros salvos, premissas ativas, as 203 contas com papel, unidade e marca de sobreposição |
| `Oria · … _files/*.js.download`, `*.css` | *bundles* minificados do Next.js que o navegador baixou junto. **Não são fonte** — a fonte é `portal/src/`. Estão aqui só para a página abrir offline com o mesmo layout |

O upload original chegou com tudo achatado na raiz do repositório; os assets voltaram para a pasta
`_files/` porque é o caminho que o próprio HTML referencia (`./Oria · … _files/…`) — achatado, a
página abria sem estilo nenhum.

**Não há segredo aqui.** Foi conferido: nenhum JWT, nenhuma chave `anon`/`service_role`, nenhuma URL
de projeto Supabase nos onze arquivos. Há dado de caso e o e-mail do usuário logado no cabeçalho —
o repositório é privado, e é o mesmo dado que o `HANDOFF.md` já discute em texto.

## Por que ficou versionado

Porque é a **única** evidência do comportamento em produção desta fase. `verificar-export.mts` ainda
não tem os asserts do modelo institucional (declarado no PR #85), então o que a tela mostra é hoje a
melhor prova disponível de que a `0042` funciona contra rótulo real — e do que ela ainda não pega.

## O que esta captura provou, e o que ela denunciou

**Funciona contra dado real** (não só contra fixture):

- a **curva de sazonalidade sai preenchida** (jan 8,4% … dez 7,0%). É a correção de
  `fn_mes_do_rotulo`: com `left(chave,3)` sobre `Faturamento Janeiro` a curva voltava vazia;
- os 12 `Faturamento Janeiro…Dezembro` aparecem como **série mensal**, fora da contagem de contas;
- `ATIVO`, `TOTAL DO ATIVO`, `RECEITA OPERACIONAL LÍQUIDA`, `LUCRO BRUTO` e mais 24 rótulos
  aparecem como **subtotal**, sem seletor de premissa;
- `Índice de liquidez corrente`, `Média mensal 2024/2025`, `Ticket médio por pedido` como
  **derivado**;
- a escala aparece **por linha**: `R$` nas linhas de `MAPA_DIVIDA` (2.680.000) ao lado de `R$ mil`
  no balanço (158.801). Antes as duas eram o mesmo número sem qualificação.

**Denunciou** (ver a análise da sessão no `HANDOFF.md`):

1. **203 contas projetáveis, ZERO com premissa vinculada** — e o seletor de sazonalidade de todas as
   203 tem uma única opção, a vazia, porque `SAZ_MENSAL` não está ativada. A curva é calculada e
   exibida, mas nenhuma linha pode consumi-la.
2. **Só as 5 premissas macro estão ativas.** Todo seletor de linha oferece apenas `CAMBIO_USD`,
   `IGPM`, `IPCA`, `PIB`, `SELIC`. Nenhuma premissa operacional foi ativada no passo 2.
3. **`setor = tecnologia` salvo num mandato de metalurgia** — a lista sugerida traz ARR, Churn, LTV
   e CAC para a Vertentes Metalúrgica.
4. **`Arrendamentos` e `Provisões` são cabeçalho de grupo tratado como conta projetável**, cada um
   marcado com `possível sobreposição` contra o seu próprio componente. `fn_papel_linha` não os
   classifica como subtotal porque não têm a palavra "total" — é a mesma família do defeito de dupla
   contagem que o `HANDOFF.md` mantém aberto.
5. **Os dois rótulos de fechamento do balanço não cobrem a mesma população.** `ATIVO` e
   `TOTAL DO ATIVO` trazem 13 ocorrências cada; `PASSIVO E PATRIMÔNIO LÍQUIDO` traz 6 e
   `TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO`, 7. Os dois `TOTAL DO …` batem em 158.801, o que é
   bom sinal — mas a coluna é `valor_ultimo` (maior módulo entre as ocorrências, para reconhecer a
   conta), **não** uma conferência de balanço: quem fecha Ativo × Passivo+PL por exercício é
   `fn_valores_por_ano` e o check da aba `Balance Sheet`. A assimetria 13 × 6 é o que merece olhar.
