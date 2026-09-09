#!/usr/bin/env bash
#
# REPUBLICAR O WORKFLOW — os três curl do runbook, com as travas no meio.
#
# POR QUE ISTO EXISTE. A sequência correta sempre esteve escrita (no cabeçalho
# de `preparar-republicacao.mjs` e em `.claude/memory/republicacao-do-n8n-perde-
# toggles.md`), mas era uma sequência de comandos soltos que o dono colava um a
# um. Em 09/09 o pedido foi explícito: "não entendi direito". Comando que só a
# engenharia consegue rodar é comando que não se roda — e a republicação é
# justamente o passo sem o qual a correção fica no repositório e não na
# produção, que já custou duas rodadas a este projeto.
#
# O QUE ELE ACRESCENTA aos três curl, e é o motivo de ser um script:
#
#   • ABORTA se o `REPLACE` sobreviver no arquivo a publicar. O JSON do
#     repositório grava `REPLACE` no id de cada credencial de propósito, para
#     não versionar nada da instalação; `preparar-republicacao.mjs` os troca
#     pelos ids reais lidos do workflow VIVO. Se sobrar um, subir quebraria as
#     14 credenciais de uma vez — e o sintoma apareceria só na próxima rodada.
#   • ABORTA se o `path` do gatilho de formulário vier vazio. Ele é atribuído
#     pelo n8n e sobrescrevê-lo TROCA A URL PÚBLICA do intake. Já se perdeu uma.
#   • ABORTA antes de publicar se a cópia local não for a do `main` atualizado
#     — republicar uma árvore velha é publicar a versão SEM as correções,
#     enquanto a equipe inteira acredita que publicou as novas.
#   • Publica só depois que as três passam, e roda o conferidor no fim. O
#     `conferir-publicado.mjs` já sai com código 1 em divergência; aqui esse
#     código vira o código de saída do script, para que "deu certo" seja uma
#     afirmação verificada e não a ausência de erro na tela.
#
# NÃO faz `PUT` do JSON do repositório direto, nunca — é o que perdeu
# `onError` em 23 nós, `retryOnFail` em 11 e o `multipleFiles` do formulário,
# em duas republicações seguidas (26/08 e 27/08).
#
# USO:
#   export N8N_URL="https://seu-n8n"        # sem barra no fim
#   export N8N_API_KEY="..."                # n8n → Settings → n8n API
#   export N8N_WORKFLOW_ID="..."            # o id na URL do editor
#   ./N8N/republicar.sh
#
#   --dry-run   faz tudo menos o PUT (prepara, confere o arquivo, e para)
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

erro() { local msg="$1"; printf '\n  ABORTADO — %s\n\n' "$msg" >&2; exit 1; }
passo() { local titulo="$1"; printf '\n=== %s\n' "$titulo"; }

# --- as três variáveis -------------------------------------------------------
for v in N8N_URL N8N_API_KEY N8N_WORKFLOW_ID; do
  [[ -n "${!v:-}" ]] || erro "falta a variável \$$v — veja o cabeçalho deste arquivo"
done
N8N_URL="${N8N_URL%/}"

# --- TRAVA 1: a cópia local é a versão que se pretende publicar? -------------
passo "1/5  a árvore local está atualizada?"
if [[ -n "$(git status --porcelain -- N8N/workflow.e1-ingestao.json)" ]]; then
  erro "N8N/workflow.e1-ingestao.json tem mudança não commitada.
           Publicar assim sobe algo que não está em nenhum commit — e ninguém
           consegue dizer depois o que foi publicado. Commite ou descarte antes."
fi
git fetch --quiet origin main 2>/dev/null || true
if ! git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
  erro "o \`main\` do remoto tem commits que esta árvore não tem.
           Rode: git checkout main && git pull origin main
           Republicar uma árvore atrasada publica a versão SEM as correções."
fi
echo "    ok — árvore limpa e não atrasada em relação a origin/main"

# --- baixar o vivo -----------------------------------------------------------
passo "2/5  baixando o workflow publicado"
# Os DOIS ficam fora do repositório. `publicar.json` carrega os ids REAIS das
# 14 credenciais e o `path` público do intake — ele nasceu na raiz e sem
# .gitignore, e uma revisão pegou (PR #204): um `git add -A` distraído
# versionaria segredo de instalação. O `--dry-run` preserva o arquivo de
# propósito, e imprime o caminho, porque inspecioná-lo é o objetivo do modo.
VIVO="$(mktemp)"; PUB="$(mktemp -t publicar.XXXXXX)"
LIMPAR_PUB=1
# `if` e não `&&`: sob `set -e`, um teste falso como ÚLTIMO comando de um trap
# de EXIT pode alterar o código de saída do script — e este script existe para
# que o código de saída signifique alguma coisa.
trap 'rm -f "$VIVO"; if [[ "$LIMPAR_PUB" == "1" ]]; then rm -f "$PUB"; fi' EXIT
curl -sS -f -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_URL/api/v1/workflows/$N8N_WORKFLOW_ID" -o "$VIVO" \
  || erro "não consegui ler o workflow. Confira \$N8N_URL, a chave e o id."
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$VIVO" \
  || erro "a resposta não é JSON válido — provavelmente a URL ou a chave estão erradas"
echo "    ok — $(node -p "JSON.parse(require('fs').readFileSync('$VIVO','utf8')).nodes.length") nós no publicado"

# --- fundir ------------------------------------------------------------------
passo "3/5  fundindo comportamento do repositório com a identidade da instalação"
node N8N/preparar-republicacao.mjs < "$VIVO" > "$PUB" \
  || erro "preparar-republicacao.mjs falhou — nada foi publicado"

# --- TRAVA 2 e 3: o arquivo a publicar está são? -----------------------------
passo "4/5  conferindo o arquivo ANTES de publicar"
# `grep -c` conta LINHAS que casam, não OCORRÊNCIAS: com o JSON numa linha só,
# ele diria "1" para 14 credenciais quebradas. A trava abortaria de qualquer
# forma, mas o número na mensagem estaria errado — e é por ele que se decide o
# que fazer em seguida. Medido na revisão do PR #204.
N_REPLACE="$(grep -o 'REPLACE' "$PUB" | wc -l | tr -d ' ')"
[[ "$N_REPLACE" == "0" ]] || erro "sobraram $N_REPLACE ocorrência(s) de REPLACE no arquivo a publicar.
           Isso quebraria as credenciais. O arquivo NÃO foi publicado; me mande
           esta mensagem."
node -e '
  const w = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  const form = (w.nodes||[]).find(n => (n.type||"").includes("formTrigger"));
  if (!form) { console.error("não achei o gatilho de formulário"); process.exit(1); }
  const p = form.parameters && form.parameters.path;
  if (!p) { console.error("o path do formulário veio VAZIO — publicar trocaria a URL pública do intake"); process.exit(1); }
  console.log("    ok — path do formulário preservado, credenciais reais, " + w.nodes.length + " nós");
' "$PUB" || erro "a conferência do arquivo reprovou — nada foi publicado"

if [[ "$DRY_RUN" == "1" ]]; then
  LIMPAR_PUB=0   # o objetivo do modo é inspecionar o arquivo; ele sobrevive à saída
  printf '\n  --dry-run: arquivo pronto e conferido. NADA foi publicado.\n'
  printf '  Ele está em %s — contém ids REAIS de credencial, não commite.\n\n' "$PUB"
  exit 0
fi

# --- publicar ----------------------------------------------------------------
passo "5/5  publicando e conferindo o que ficou de pé"
curl -sS -f -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
  "$N8N_URL/api/v1/workflows/$N8N_WORKFLOW_ID" --data-binary "@$PUB" -o /dev/null \
  || erro "o PUT falhou. O workflow pode ter ficado no estado anterior — confira no editor."

curl -sS -f -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_URL/api/v1/workflows/$N8N_WORKFLOW_ID" | node N8N/conferir-publicado.mjs

printf '\n  PUBLICADO E CONFERIDO.\n\n'
# Este aviso já afirmou "o FINGERPRINT_EXTRACAO mudou" como se fosse sempre
# verdade. NÃO é: a correção da régua do PR #204 mexeu no jsCode de 4 nós e
# deixou o fingerprint intacto (d1a77ddf7937b595), enquanto o alias HEADCOUNT
# do PR #203 mudou. Só quem mexe em SYSTEM_PROMPT, MODELO_EXTRACAO ou no schema
# muda o fingerprint — e só nesse caso o dedup da 0118/0127, que é por
# (hash, fingerprint), deixa de casar. Aviso que mente por excesso ensina a
# ignorar aviso.
printf '  Se o FINGERPRINT_EXTRACAO tiver mudado nesta publicação, a primeira\n'
printf '  rodada RE-EXTRAI cada documento de um caso já processado (dedup da\n'
printf '  0118/0127 é por hash+fingerprint). Confira contra a publicação\n'
printf '  anterior antes de rodar um lote grande — ver ESTADO.md, "O que só o\n'
printf '  dono pode fazer". Se não mudou, nada é re-extraído.\n\n'
