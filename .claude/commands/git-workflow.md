---
model: claude-opus-5
---

> **AJUSTE DESTE REPOSITÓRIO — leia antes de seguir o texto abaixo.**
> Este comando veio de `wshobson/commands` e manda chamar agentes que **não existem aqui**
> (`code-reviewer`, `test-automator`, `backend-architect`, `tdd-orchestrator`…): eles são do
> repositório de agentes companheiro daquele autor. Os agentes DESTE projeto estão em
> `.claude/agents/` e listados no `CLAUDE.md`: `migrations-postgres`, `n8n-workflow`,
> `portal-export`, `suites-invariantes`, `revisor-defeito-silencioso`, `explorador`,
> `estado-e-handoff`. Onde o texto pedir um agente fora dessa lista, use o equivalente daqui
> — ou faça direto. Não invente `subagent_type`: despacho para agente inexistente falha.


Complete Git workflow using specialized agents:

1. code-reviewer: Review uncommitted changes
2. test-automator: Ensure tests pass
3. deployment-engineer: Verify deployment readiness
4. Create commit message following conventions
5. Push and create PR with proper description

Target branch: $ARGUMENTS
