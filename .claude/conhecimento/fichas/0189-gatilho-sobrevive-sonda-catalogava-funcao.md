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

Migration 0189 cria o tipo `gatilho` (objeto `tabela.nome_do_gatilho`, presente só com `tgenabled` em 'O'/'A'), reemite a função inteira a partir da 0147, cataloga os 9 gatilhos não-internos de main (6 originais + os 3 da F1.7, entrados no merge do #238). O teste `Supabase/test/sonda_ve_gatilho.test.sql` (17 asserts, igualdade de conjuntos) reprova 6 blocos quando o ramo gatilho é desligado e 1 quando 'R' é aceito como habilitado.

**Risco de ordem:** até a `0183` da F1.7, `instalacao_cobertura` aceita valor menor — e já aconteceu em produção (a `0182` depois da `0188`). A `0183` cria `trg_instalacao_cobertura_nao_regride`, que fecha isso.

**F1.7:** os três gatilhos dela (`trg_entidade_controlador_soma_maxima`, `trg_entidade_forma_de_controle_tem_vinculo`, `trg_instalacao_cobertura_nao_regride`) entraram no catálogo da 0189 no merge do `main`. Por isso, em produção, a 0189 vai DEPOIS da 0183. A igualdade de conjuntos do teste é o que obriga o próximo gatilho a entrar também.
