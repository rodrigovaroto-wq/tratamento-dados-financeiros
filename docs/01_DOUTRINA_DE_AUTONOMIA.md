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
