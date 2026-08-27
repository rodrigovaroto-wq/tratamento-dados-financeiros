// O JSON DO WORKFLOW PUBLICADO, LIDO DA ENTRADA PADRÃO — em um lugar só.
//
// Os dois conferidores de publicação (`conferir-publicado.mjs` e
// `preparar-republicacao.mjs`) começam igual: recebem pela entrada padrão o JSON
// que veio do editor do n8n ou da API REST. O bloco era o MESMO nos dois, com as
// mesmas três decisões — e cada uma delas foi paga com um erro real, então
// duplicá-las é combinar de esquecer uma das duas cópias:
//
//   1. `isTTY` distingue "esqueceu de redirecionar" de "o JSON está vindo". Sem
//      isso o script fica pendurado esperando alguém digitar um workflow inteiro;
//   2. a leitura é por STREAM, e não `readFileSync(0)`: com `<` o descritor 0 é
//      arquivo comum e a síncrona funciona, mas com `|` ele é um cano em modo não
//      bloqueante e a mesma chamada estoura `EAGAIN` — medido, e o `curl | node`
//      é justamente a forma documentada de chamar;
//   3. o envelope: o editor entrega o workflow na raiz, a API REST e o MCP o
//      entregam dentro de `{workflow:…}` ou `{data:…}`.
//
// E O CAMINHO NÃO ENTRA AQUI DE PROPÓSITO. A primeira versão destes scripts
// recebia o arquivo por argumento e o abria; hoje quem abre é o shell, com as
// permissões de quem digitou. É a diferença entre validar um risco e não o ter.

/**
 * Lê e devolve o workflow publicado, já sem envelope.
 *
 * Encerra o processo com código 2 — e uma mensagem que diz o que fazer — quando
 * não há nada na entrada ou o que veio não é JSON. É um utilitário de linha de
 * comando: falhar com pilha de exceção aqui seria pior que falhar dizendo o uso.
 */
export async function lerWorkflowDaEntradaPadrao(linhasDeUso) {
  if (process.stdin.isTTY) {
    for (const linha of linhasDeUso) console.error(linha);
    process.exit(2);
  }

  const pedacos = [];
  for await (const p of process.stdin) pedacos.push(p);

  let bruto;
  try {
    bruto = JSON.parse(Buffer.concat(pedacos).toString('utf8'));
  } catch (e) {
    console.error(`recusado: a entrada padrão não trouxe um JSON válido (${e.message}).`);
    process.exit(2);
  }
  return bruto.workflow ?? bruto.data ?? bruto;
}

/**
 * Este arquivo está sendo EXECUTADO, ou só importado por um teste?
 *
 * `import.meta.url` termina com o nome do arquivo que o node recebeu na linha de
 * comando quando ele é o ponto de entrada. Sem isto, importar qualquer um dos
 * dois scripts num teste dispararia a leitura da entrada padrão.
 */
export function ehExecucaoDireta(urlDoModulo) {
  return Boolean(process.argv[1]) && urlDoModulo.endsWith(process.argv[1].split('/').pop());
}
