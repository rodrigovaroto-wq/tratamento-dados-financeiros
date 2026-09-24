---
id: gatilho-sobrevive-sonda-catalogava-funcao
tipo: defeito
toca:
  - Supabase/migrations/0189_o_gatilho_que_a_sonda_nao_via.sql
  - Supabase/test/sonda_ve_gatilho.test.sql
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0189_o_gatilho_que_a_sonda_nao_via.sql#tgenabled
ancora_sha: 6645be54b8eb
---

# A função do gatilho sobrevive ao gatilho — a sonda catalogava o vínculo errado

`fn_instalacao_conferir()` tinha seis tipos de requisito (tabela, coluna, função, corpo, seed, comportamento) e nenhum para "o gatilho está instalado e ligado". Quando o catálogo precisava afirmar isso, catalogava a **FUNÇÃO** do gatilho como tipo `funcao`.

O defeito: **a função sobrevive a `drop trigger` e a `alter table ... disable trigger`.** Um DBA depurando um deadlock ou uma restauração parcial de backup pode desligar a guarda silenciosamente — a sonda continua vendo "presente", porque o que ela mediu nunca foi o vínculo.

Migration 0189 cria o tipo `gatilho` (objeto `tabela.nome_do_gatilho`, presente só com `tgenabled` em 'O'/'A'), reemite a função inteira a partir da 0147, cataloga os 6 gatilhos não-internos de main. O teste `Supabase/test/sonda_ve_gatilho.test.sql` (17 asserts, igualdade de conjuntos) reprova 6 blocos quando o ramo gatilho é desligado e 1 quando 'R' é aceito como habilitado.

**Risco:** cobertura declarada recua em produção se 0182/0183/0187/0188 forem aplicadas DEPOIS da 0189, pois cada uma grava `ate_migration` menor. Aplicar em ordem numérica.

**F1.7 bloqueador:** PR #238 tem `trg_entidade_controlador_soma_maxima` e `trg_entidade_forma_de_controle_tem_vinculo` — o `run.sh` (teste `sonda_ve_gatilho`) ficará vermelho até esses dois serem catalogados com tipo gatilho. Deliberado.
