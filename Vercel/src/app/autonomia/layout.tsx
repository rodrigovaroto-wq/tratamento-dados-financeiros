// O painel de autonomia usa a MESMA moldura dos mandatos (cabeçalho, e-mail,
// sair). O layout é um componente comum, então reaproveitá-lo aqui evita uma
// segunda cópia do cabeçalho que sairia de sincronia na primeira mudança.
//
// Por que a rota é `/autonomia` e não `/casos/autonomia`: o dial é GLOBAL — vale
// para todos os mandatos, não é estado de um. Pendurar em `/casos/` daria a
// entender que se configura autonomia por caso, o que não é verdade, e ainda
// colidiria visualmente com a rota dinâmica `/casos/[id]`.
export { default } from "@/app/casos/layout";
