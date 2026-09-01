---
name: republicacao-do-n8n-perde-toggles
description: republicar o workflow pela API perde onError em 23 nós, retryOnFail em 11 e o multipleFiles do campo de arquivo — sem ele o intake aceita um documento por vez
metadata:
  type: reference
---

Duas republicações seguidas perderam a mesma família de coisas, e é por isso que
`N8N/preparar-republicacao.mjs` existe. Nunca faça `PUT` do JSON do repositório direto:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/preparar-republicacao.mjs > publicar.json
curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
  "$N8N_URL/api/v1/workflows/$ID" --data-binary @publicar.json
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/conferir-publicado.mjs
```

O pior dos toggles perdidos é o **`multipleFiles: true`** do campo de arquivo do formulário: sem
ele o intake aceita **um documento por vez**, e o sintoma só aparece quando alguém tenta subir 190
arquivos. Confira esse toggle no editor antes de uma rodada grande.

E o que nenhuma suíte cobre: `N8N/test/workflow-sim.test.mjs` mede o JSON **do repositório**, não
o que está publicado no n8n. Mudança de topologia (nó novo, `executeOnce`, `queryBatching`) não
existe em produção até a republicação — e nenhum teste verde diz o contrário.
