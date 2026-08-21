# 01 — Doutrina de Autonomia

Este é o núcleo conceitual da v2. É o que concilia a decisão de **"construir todo o workflow
primeiro"** com a exigência de **"sem brechas para erros"**.

## A tensão que a doutrina resolve

"Construir tudo primeiro" + "sem brechas" se contradizem se tratados de forma ingênua: montar
as camadas interpretativas (classificação contábil, reconciliação, extração de linhas) de uma
vez é exatamente onde se **automatiza erro em escala**. Além disso, *"sem brechas" absoluto
não existe* — nenhum sistema é infalível.

A doutrina entrega o que é de fato atingível: **fail-safe por construção**. O workflow inteiro
é construído de uma vez, mas a segurança **não vem de cortar estágios** — vem de cada estágio
nascer no seu **nível de autonomia mínimo seguro** e só subir com dado de calibração. O
sistema é completo no dia 1; a **confiança é conquistada estágio a estágio**.

## Os níveis de autonomia (o "dial" de cada estágio)

| Nível | Nome | Comportamento |
|---|---|---|
| **N0** | Sombra | O estágio roda, registra a saída, mas **não influencia decisão**. Existe só para medir antes de confiar. |
| **N1** | Sugestão + revisão 100% | A saída aparece como sugestão; **humano confirma todo item**. |
| **N2** | Auto-clear + resto p/ humano | Acima do threshold, autônomo; abaixo, vai para humano. |
| **N3** | Autônomo + auditoria por amostragem | Roda sozinho; humano audita apenas amostra. |

Cada estágio do workflow tem seu **próprio dial**, registrado no Supabase e visível/ajustável
no painel de autonomia (Vercel). O nível é estado do sistema, não constante de código.

## Regra de teto por natureza do estágio (inegociável)

| Tipo de estágio | Nasce em | Teto |
|---|---|---|
| Determinístico objetivo (completude, integridade de arquivo, identidades aritméticas com pré-condições OK, versionamento) | N2 | N3 |
| Extração de identificadores (tipo/período/entidade) | N1 | N2 |
| Extração de linhas/tabelas financeiras | N0 | N2 |
| Classificação documento→checklist | N1 | N2 |
| Reconciliação Classe A (aritmética) | N1 | N2 |
| Reconciliação Classe B/C (semi/interpretativa) | N0 | **N1** (nunca autônomo) |
| Classificação contábil (recorrente/EBITDA) | N0 | **N1** (nunca vira número sem aceite humano) |

**Calibrar = subir o dial de um estágio**, guiado pela concordância humano-máquina medida
contra o golden set. É literalmente o "ajustar as partes mal calibradas depois". Toda subida
de nível é uma **decisão versionada e reversível** (gera evento na trilha de auditoria).

## O que "sem brechas" significa de fato — os 8 fechamentos fail-safe

1. **Default-para-humano.** Qualquer confiança abaixo do threshold, ou qualquer estágio não
   calibrado (N0/N1), cai para revisão. Nunca para avanço silencioso.
2. **Gate de captura com saída.** Input ilegível/corrompido → **transcrição humana
   assistida**, nunca dead-end de pendência infinita.
3. **Pré-condições explícitas.** Toda etapa objetiva declara suas premissas (período/
   entidade/escopo/moeda); se não satisfeitas → pendência, não resultado falso-limpo.
4. **Pendências bloqueantes não-sobrepujáveis** (lista fechada) + teto de ressalvas por caso.
5. **Anti-ancoragem.** Nenhum número entra na base de modelagem sem **evento de aceite humano
   explícito**.
6. **Confiança de LLM ≠ probabilidade calibrada.** Só se sobe autonomia com concordância
   medida; nunca por "achismo de score".
7. **Trilha append-only** de tudo; toda decisão e toda mudança de autonomia é reversível.
8. **Reconciliação não "reconcilia" o interpretativo.** No máximo *aproxima para humano*.

**Onde o nº 2 é EXECUTADO (`db/migrations/0129_transcricao_humana_assistida.sql` + a planilha no
portal, 20/08/2026).** Era o único dos oito sem código: o gate existia (a `0010`/`0020` abrem
`arquivo_ilegivel`) e a saída existia em outra forma — reenviar ao cliente, rejeitar —, mas a
transcrição assistida em si, que é a saída que serve quando o cliente **não tem** outra via do
arquivo, nunca foi construída. Agora: `fn_registrar_transcricao_humana` grava as linhas digitadas
numa **versão nova** do documento (doutrina da `0026`), com a versão ilegível preservada contando por
que houve transcrição; as **guardas de extração não rodam** (elas pegam alucinação de modelo) e a
confiança fica **nula**, porque não existe autoavaliação de pessoa; a pendência de ilegibilidade
fecha com o **nome de quem transcreveu**; e `campo_extraido.origem_valor` mantém a linha transcrita
**fora da medição da extração** — acerto de máquina medido contra número que uma pessoa digitou não
mediria nada. A forma é planilha modelo (`portal/src/lib/transcricao.ts`), não formulário web:
ninguém digita balanço em campo de tela se puder usar Excel.

## Regra de ouro

> **Nada de subir o dial de autonomia de um estágio interpretativo sem golden set e
> concordância medida.** É o que mantém "construir tudo primeiro" à prova de erro.

**Onde ela é EXECUTADA (`db/migrations/0126_golden_set.sql`, 19/08/2026).** Esta regra passou da
`0019` até a `0126` sendo apenas texto: `fn_mudar_dial` (0041) conferia o teto e nada mais, então
subir a extração para N2 com um motivo em texto livre era aceito — e foi assim que ela subiu.
A partir da `0126`:

- `fn_mudar_dial` **recusa** subida que alcance N2/N3 num estágio de `natureza = 'interpretativo'`
  sem uma rodada de golden set congelada que satisfaça `golden_criterio`;
- a **natureza** de cada estágio (a primeira coluna da tabela de teto acima) é coluna de
  `estagio_autonomia`, não lista dentro de uma função;
- subir por decisão continua possível, com `p_sem_medicao_porque` — um motivo, não um sinalizador —
  que grava `mudanca_dial_sem_medicao` na trilha e deixa `base_do_nivel = 'declarada'`. É isso que
  torna "declarada" e "medida" distinguíveis, o que antes não eram;
- **descer nunca pede nada.** Freio que exige evidência não é freio.

O portão morde na entrada do **auto-clear**, não em toda subida: N1 mantém revisão de 100% e o
fechamento #5 (anti-ancoragem) inteiro, e cobrar medição para exibir uma sugestão travaria o caminho
que esta doutrina manda percorrer — os estágios nascem baixos justamente para subir.

## Como se mede a concordância quando não há rotulagem (decisão de 21/08/2026)

A regra de ouro criou uma consequência aritmética que ficou aberta por três sessões, e ela merece
estar escrita aqui e não só num mapa de execução.

A `0126` passou a **executar** a regra. Na sessão 53 o dono removeu o fluxo de rotulagem manual: o
objetivo é o sistema operar sem triagem humana, e uma tela que pede uma tarde de mesa por rodada
orienta o contrário. Só que sem rotulagem nenhuma rodada de golden set congela, e sem rodada
congelada nenhum estágio interpretativo sobe. **O sistema passou a se recusar a certificar a si
mesmo.** Isso está certo, e é um estado terminal: não é um caminho, é uma parede.

**A decisão do dono, em 21/08, foi a seguinte: o veredito que o trabalho normal já produz passa a
contar, declarando o que ele é.** Toda vez que o analista confirma ou corrige o palpite da máquina
na tela de revisão, ele emite um rótulo — de graça, sem tarde de mesa. A `0136`
(`fn_veredito_producao`) lê esse rastro e o liga ao dial como terceira porta.

**As três portas para subir um estágio interpretativo a N2/N3, em ordem de força da evidência:**

| Porta | `base_do_nivel` | O que o número vale |
|---|---|---|
| Rodada de golden set congelada | `medida` | Rótulo **cego**: quem rotulou não viu o palpite da máquina. É a única que sustenta o número para fora da casa |
| Veredito de produção suficiente | `medida_por_veredito` | Rótulo **enviesado**: quem julgou viu o palpite antes de decidir. Mede um **piso** |
| Motivo assumido por escrito | `declarada` | Não é medição nenhuma. Continua possível, continua contável na trilha |

**Por que o piso é honesto e a média não seria.** O viés de confirmação tem direção conhecida:
concordar com o que já está na tela é mais barato que discordar, então o número sai para cima. Um
piso enviesado responde "a máquina acerta **pelo menos** isto", que é uma afirmação verdadeira e
útil. O que seria desonesto é chamar esse número de concordância medida e deixá-lo indistinguível do
rótulo cego na mesma coluna — por isso `medida_por_veredito` é valor próprio, e o assert mais
importante da suíte é justamente que ele **nunca** vira `medida`.

**O que esta decisão NÃO autoriza:**

- **subir dial porque a rodada foi bem.** É o risco que a `0126` foi escrita para impedir, e dois
  níveis declarados eram falsos quando ela chegou. Rodada boa não é medição;
- **afrouxar `fn_mudar_dial`** para destravar alguma coisa. Se um estágio não sobe, a leitura certa
  é que falta evidência, não que falta permissão;
- **passar do teto por natureza do estágio.** Nenhuma quantidade de veredito sobe reconciliação
  Classe B/C ou classificação contábil acima de N1. O teto é doutrina e só muda por migration.

**A rotulagem cega continua sendo o caminho, e não foi apagada.** O caminho de escrita da `0130`
está inteiro no banco, e o dia em que for preciso um número que sustente subir dial para fora da
casa — auditoria, cliente, credor — é rodada de golden set que responde. A saída C do `B3`
(exportar o lote cego em planilha, rotular fora do portal, importar de volta) fica guardada para
esse dia; a máquina de ida e volta já existe desde a `0129`.
