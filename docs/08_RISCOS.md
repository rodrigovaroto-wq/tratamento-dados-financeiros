# 08 — Riscos e Falhas Prováveis

| # | Risco | Sev. | Mitigação |
|---|---|---|---|
| 1 | **OCR/captura ruim contamina tudo** (docs BR de cliente em distress: foto de balancete, PDF torto, Excel bagunçado) | Crítica | Gate de captura + **transcrição humana assistida**; baseline de qualidade medido em F0; extração de linhas nasce em N0 |
| 2 | **Automatizar erro em escala** (construir tudo de uma vez) | Crítica | **Doutrina de Autonomia**: interpretativo nasce N0/N1; subir dial só com golden set |
| 3 | **Viés de ancoragem** (sugestão da máquina enviesa o analista) | Alta | Classificação em sombra; nenhum número sem aceite humano explícito |
| 4 | **Revisão humana vira gargalo** | Alta | Auto-clear, lote, SLA/aging, métrica de % de toque humano |
| 5 | **"Aceitar com ressalva" vira carimbo** | Alta | Bloqueantes não-sobrepujáveis + teto + expiração |
| 6 | **Taxonomia trava o projeto** (política interna; analistas discordam) | Alta | Dono único; critério "bom o suficiente para começar"; itera |
| 7 | **LGPD** (docs pessoais de sócios, garantias = PII) | Alta | Classificação de sensibilidade, RLS/escopo, retenção, acesso auditado — desenhado em F0 |
| 8 | **Drift de taxonomia** (Obsidian ≠ runtime) | Alta | Fonte da verdade no Postgres; Obsidian espelha |
| 9 | **N8N vira dono acidental do estado** | Alta | N8N stateless; Supabase dono do estado |
| 10 | **Fronteiras "objetivas" vazam** (completude depende de classificação; reconciliação depende de período/escopo) | Média | Pré-condições explícitas → pendência, não falso-OK |
| 11 | **Confiança de LLM tratada como métrica calibrada** | Média | Só sobe dial com concordância medida contra golden set |
| 12 | **Falsa sensação de completude** (checklist completo, conteúdo errado) | Média | Completude e validade são status separados |
| 13 | **Excesso de confiança do time após sucesso inicial** | Média | "Não é 100% automático" como princípio; dial visível e auditado |
| 14 | **Escopo inflado** (10 camadas, dois produtos, modelagem) | Média | Um produto (Reestruturação); core completo mas M&A/cliente/analítico fora |
| 15 | **Bespoke vira passivo operacional** (boutique, poucas mãos) | Média | Decisão build-vs-buy registrada em F0; dono de operação nomeado |
| 16 | **Thresholds mal calibrados** | Média | Golden set + calibração por override; por-campo/por-tipo |
| 17 | Dependência de fornecedor/modelo LLM | Baixa-Média | Abstrair chamada; LLM só na ambiguidade residual |
