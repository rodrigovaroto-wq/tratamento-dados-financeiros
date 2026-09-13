#!/usr/bin/env bash
# A MEDIÇÃO DA LINHA DE BASE, reprodutível — ver BASELINE.md.
#
# Roda os mesmos cinco `grep` que uma sessão roda hoje para responder as cinco
# perguntas, e imprime quantos bytes cada um devolve. Sem argumentos.
#
#   bash .claude/conhecimento/medir.sh
#
# POR QUE ELE EXISTE: um número de "antes" que ninguém consegue reproduzir é um
# número que a próxima sessão vai ter de aceitar na fé. Este roda em 2 segundos.
set -u
cd "$(dirname "$0")/../.." || exit 1

medir() {
  local nome="$1"; shift
  local saida; saida=$(eval "$@" 2>/dev/null)
  printf '%-34s %8d bytes %5d linhas\n' "$nome" "${#saida}" "$(printf '%s' "$saida" | grep -c '')"
}

echo "CUSTO HOJE — o grep que responde cada pergunta"
medir "1-cadencia-73s" \
  "grep -rn 'SEGUNDOS_POR_DOCUMENTO\|73' portal/src/lib/espera-do-lote.ts N8N/build-workflow.mjs"
medir "2-quem-chama-fn_reconciliar_caso" \
  "grep -rn 'fn_reconciliar_caso' --include='*.ts' --include='*.mjs' --include='*.json' --include='*.sql' ."
medir "3-upload-grande-tentativas" \
  "grep -rni 'upload\|413\|4,5 MB' HANDOFF.md portal/README.md 'Arquitetura do Sistema/7 Marca/PRODUCT.md'"
medir "4-portao-do-kit-basico" \
  "grep -rn 'kit-basico\|kit_basico\|Kit Básico' .github/workflows/suites.yml portal/scripts/verificar-kit-basico.mts Supabase/migrations/*.sql"
medir "5-migration-da-sonda" \
  "grep -rln 'fn_instalacao_conferir' Supabase/migrations/ && grep -rn 'fn_instalacao_conferir' --include='*.mjs' --include='*.ts' --include='*.md' ."

echo
echo "CUSTO COM O ÍNDICE — a mesma pergunta, um comando"
for p in "cadência extração 73" "fn_reconciliar_caso" "upload lote grande 413" "kit básico portão" "fn_instalacao_conferir"; do
  saida=$(node .claude/conhecimento/buscar.mjs "$p" 2>/dev/null)
  printf '%-34s %8d bytes %5d linhas\n' "${p:0:32}" "${#saida}" "$(printf '%s' "$saida" | grep -c '')"
done
