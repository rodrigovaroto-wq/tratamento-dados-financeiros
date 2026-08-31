# Oria — Sistema de Intake e Prontidão de Dados (Workflow Operacional)

Base de arquitetura e decisão do sistema interno que transforma as submissões documentais
dos clientes da Oria em uma **base estruturada, completa, formalmente válida, reconciliada e
auditável**, com um portão explícito de go/no-go para análise.

> Isto é documentação de arquitetura e decisão. **Não há código nesta etapa.** A taxonomia
> canônica e o schema físico são registrados quando fechados com o time.

## Decisões travadas

1. **Produto inicial: Reestruturação** (dívida, mapa de dívida, fluxo de caixa,
   mútuos/intragrupo). M&A vem depois.
2. **Foco inicial: motor interno** (triagem/completude/pendências/aprovação). Portal do
   cliente vem depois.
3. **O MVP é o workflow COMPLETO.** Constrói-se todo o fluxo ponta a ponta na primeira
   versão; depois calibram-se as partes mal ajustadas. Não há corte de estágios do core nem
   entrega faseada por feature.

## Doutrina de Autonomia (em um parágrafo)

O workflow inteiro é construído de uma vez, mas a segurança não vem de cortar estágios — vem
de cada estágio nascer no seu **nível de autonomia mínimo seguro** (N0 sombra → N1 sugestão →
N2 auto-clear → N3 autônomo) e só subir com dado de calibração. O determinístico já nasce
autônomo; **tudo interpretativo nasce em sombra ou sugestão, com humano obrigatório no loop**.
"Ajustar as partes mal calibradas" significa **subir o dial de cada estágio**, e só quando a
concordância humano-máquina medida contra o golden set provar que pode. O sistema é completo
no dia 1, mas **não confia em si mesmo até medir que pode**. Ver
[`01_DOUTRINA_DE_AUTONOMIA.md`](01_DOUTRINA_DE_AUTONOMIA.md).

## Prompts e memória do agente

O fluxo de trabalho assistido por IA deste repositório está em
[`prompts/README.md`](prompts/README.md) (os prompts coláveis, nenhum deles guardando estado),
no `CLAUDE.md` da raiz (carregado em toda sessão) e em `.claude/` (memória, especialistas e
hooks). O `PROMPT_CONTINUACAO.md` foi aposentado — ele explica por quê.

## Índice

| Documento | Conteúdo |
|---|---|
| [`00_VISAO_E_ESCOPO.md`](00_VISAO_E_ESCOPO.md) | Leitura crítica, redefinição madura, escopo negativo |
| [`01_DOUTRINA_DE_AUTONOMIA.md`](01_DOUTRINA_DE_AUTONOMIA.md) | Níveis de autonomia, tetos por estágio, fail-safe |
| [`02_ARQUITETURA_FUNCIONAL.md`](02_ARQUITETURA_FUNCIONAL.md) | Estágios, portões, transversais, stack |
| [`03_MVP_E_ROADMAP.md`](03_MVP_E_ROADMAP.md) | MVP como workflow completo; roadmap construir→calibrar |
| [`04_RECONCILIACAO.md`](04_RECONCILIACAO.md) | Classes A/B/C, materialidade, o que é automático |
| [`05_CLASSIFICACAO_CONTABIL.md`](05_CLASSIFICACAO_CONTABIL.md) | Taxonomia fechada, sugestão, override, anti-ancoragem |
| [`06_HUMAN_IN_THE_LOOP.md`](06_HUMAN_IN_THE_LOOP.md) | Checkpoints, papéis, calibração, auditoria |
| [`07_STATUS_E_PENDENCIAS.md`](07_STATUS_E_PENDENCIAS.md) | Máquina de status, severidades, limites do portão |
| [`08_RISCOS.md`](08_RISCOS.md) | Riscos prováveis e mitigações |
| [`09_PLANO_DE_EXECUCAO.md`](09_PLANO_DE_EXECUCAO.md) | Alterações, plano executável por fase, próximos passos |
| [`10_DADOS_RETENCAO_E_LGPD.md`](10_DADOS_RETENCAO_E_LGPD.md) | Onde o dado do cliente mora, retenção, recuperação e quem vê o quê |

Fora da série numerada: [`PRONTIDAO_POR_ESTAGIO.md`](PRONTIDAO_POR_ESTAGIO.md) mede o projeto
contra o objetivo do `00` — estágio por estágio (ingestão, tratamento, 1º export, modelagem, 2º
export), com o que não está 100% e o que já foi fechado. Declara no fim o que NÃO cobriu.

[`MAPA_DE_EXECUCAO.md`](MAPA_DE_EXECUCAO.md) é **o que falta até o projeto
fechar**, em ordem, com o critério de pronto de cada bloco e a distinção entre o que é pendência, o
que é decisão do dono e o que é espera por dado de terceiro. Os três documentos de estado respondem
perguntas diferentes: `ESTADO.md` diz onde estamos, `HANDOFF.md` diz como chegamos, e este diz para
onde vamos.

[`ACEITE.md`](ACEITE.md) é o aceite de um `.xlsx` exportado — 10 itens que
exigem o Excel de verdade (o arquivo abre, o gráfico desenha, o dropdown reprojeta), com o resto
respondido pelo comando `portal/scripts/auditar-xlsx.mts`.

[`referencia/`](referencia/) guarda os documentos que o **dono** subiu como
fonte — o `onboarding.pdf` (67 páginas, citado por seção em `HANDOFF.md` e `db/README.md`) e o
`modelo-base.xlsx` (a planilha que `portal/src/lib/modelo-institucional.ts` reconstrói). Os dois
estavam soltos na raiz e sem extensão.

## Stack (referência)

Supabase (Postgres + Storage + Auth + Realtime — fonte da verdade do estado), N8N
(orquestração stateless), Vercel (portal interno + fila de revisão + painel de autonomia),
Claude Code (apoio à construção), Obsidian (conhecimento e espelho legível da taxonomia).

Fundamento reutilizado: o projeto `clipping-news` já prova esta stack (Supabase
Postgres+pgvector, N8N 2.27.4, split determinístico-vs-LLM, thresholds calibrados depois com
dados reais). Pegadinhas herdadas em `clipping-news/docs/DECISOES_E_APRENDIZADOS.md`.
